#!/usr/bin/env python3
"""Evaluate the two reference tasks using the actual app, without rule answers."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("weight_image", type=Path)
    parser.add_argument("count_image", type=Path)
    parser.add_argument("--binary", default=".build/debug/OfflineLens")
    parser.add_argument("--iterations", type=int, default=3)
    parser.add_argument("--output", type=Path, default=Path(".local-ai/benchmark.json"))
    parser.add_argument("--delete-failed", action="store_true", help="Delete the selected candidate files immediately after a failed evaluation")
    args = parser.parse_args()
    if args.iterations < 1:
        parser.error("iterations must be positive")
    records = []
    for label, image in [("weight", args.weight_image), ("count", args.count_image)]:
        for index in range(args.iterations):
            started = time.monotonic()
            result = subprocess.run([args.binary, "--check-image", str(image.resolve()), "--model-only", "--trace-model"],
                                    capture_output=True, text=True, timeout=75)
            answer = result.stdout.split("AI 답변 · 원문과 대조해 주세요\n\n")[-1].split("총 소요:")[0].strip()
            # Require the actual concise answer, not an example or an OCR digit.
            candidate = re.sub(r"^(?:정답|답|answer)\s*[:：]\s*", "", answer, flags=re.I).strip()
            if label == "weight":
                passed = re.fullmatch(r"3\s*(?:kg|kilograms?|킬로그램)", candidate, re.I) is not None
            else:
                # Judge the answer before the explanation, not digits in OCR.
                passed = re.fullmatch(r"4\s*(?:개|items?|objects?)", candidate, re.I) is not None
            passed = passed and result.returncode == 0
            record = {"task": label, "iteration": index + 1, "passed": passed, "seconds": round(time.monotonic() - started, 2),
                      "answer": answer, "stdout": result.stdout, "stderr": result.stderr, "exit_code": result.returncode}
            records.append(record)
            print(f"{label} {index + 1}: {'PASS' if passed else 'FAIL'} ({record['seconds']}s)\n{answer}", flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n")
    print(f"Result: {sum(r['passed'] for r in records)}/{len(records)}", flush=True)
    passed = all(r["passed"] for r in records)
    if not passed and args.delete_failed:
        root = Path(".local-ai")
        manifest_path = root / "manifest.json"
        manifest = json.loads(manifest_path.read_text())
        files = manifest.get("model_files", [{"name": manifest["model"]}])
        for entry in files:
            name = entry["name"]
            if Path(name).name != name or not name.endswith(".gguf"):
                raise ValueError("Invalid model filename")
        for entry in files:
            (root / "models" / entry["name"]).unlink(missing_ok=True)
        manifest_path.unlink()
        print("Failed candidate deleted.", flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
