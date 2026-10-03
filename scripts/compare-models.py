#!/usr/bin/env python3
"""Compare installed candidates under the same OCR, prompt and runtime."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("weight_image")
    parser.add_argument("count_image")
    parser.add_argument("models", nargs="+")
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--binary", default=".build/debug/OfflineLens")
    args = parser.parse_args()
    root = Path(".local-ai")
    manifest = root / "manifest.json"
    original = manifest.read_bytes()
    summaries = []
    try:
        for name in sorted(args.models, key=lambda n: (root / "models" / n).stat().st_size):
            path = root / "models" / name
            if path.name != name or not path.is_file():
                raise ValueError("Use an installed model filename")
            sha = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    sha.update(chunk)
            config = json.loads(original)
            for field in ("model_files", "model_revision", "quantization"):
                config.pop(field, None)
            config.update(model=name, model_sha256=sha.hexdigest(), model_bytes=path.stat().st_size)
            manifest.write_text(json.dumps(config, indent=2) + "\n")
            report = root / f"{path.stem}-comparison.json"
            print(f"\nCandidate: {name} ({path.stat().st_size / 1e6:.1f} MB)", flush=True)
            result = subprocess.run([sys.executable, "scripts/benchmark-images.py", args.weight_image, args.count_image,
                                     "--iterations", str(args.iterations), "--binary", args.binary, "--output", str(report)])
            summaries.append({"model": name, "bytes": path.stat().st_size, "sha256": sha.hexdigest(),
                              "passed": result.returncode == 0, "report": str(report)})
    finally:
        manifest.write_bytes(original)
    (root / "comparison.json").write_text(json.dumps(summaries, indent=2) + "\n")
    print("\nPassing candidates:", flush=True)
    for summary in summaries:
        if summary["passed"]:
            print(summary["model"], summary["bytes"], flush=True)


if __name__ == "__main__":
    main()
