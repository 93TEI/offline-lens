#!/usr/bin/env python3
"""Verify the packaged app with OS-denied network access (including children)."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("expected")
    parser.add_argument("--binary", type=Path, default=Path("dist/Offline Lens.app/Contents/MacOS/OfflineLens"))
    parser.add_argument("--output", type=Path, default=Path(".local-ai/offline-check.json"))
    args = parser.parse_args()
    binary, image = args.binary.resolve(), args.image.resolve()
    with tempfile.TemporaryDirectory(prefix="offlinelens-network-check-") as folder:
        policy = Path(folder) / "deny-network.sb"
        policy.write_text("(version 1)\n(allow default)\n(deny network*)\n")
        wrapper = ["/usr/bin/sandbox-exec", "-f", str(policy)]
        probe = subprocess.run(wrapper + [sys.executable, "-c",
            "import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.sendto(b'test',('127.0.0.1',9))"],
            capture_output=True, text=True, cwd=folder, timeout=10)
        if probe.returncode == 0 or "Operation not permitted" not in probe.stderr:
            raise RuntimeError("Network-denial probe failed; refusing to label the run offline")
        print("PASS: OS network-denial probe", flush=True)
        started = time.monotonic()
        # Run outside the project so a missing bundled model cannot fall back to .local-ai.
        run = subprocess.run(wrapper + [str(binary), "--check-image", str(image), "--model-only", "--trace-model"],
            capture_output=True, text=True, cwd=folder, timeout=90)
        marker = "AI 답변 · 원문과 대조해 주세요\n\n"
        answer = run.stdout.split(marker, 1)[1].split("총 소요:", 1)[0].strip() if marker in run.stdout else ""
        passed = run.returncode == 0 and answer == args.expected
        report = {"method": "sandbox-exec: deny network*; app and child runtime; cwd outside project",
                  "network_probe_denied": True, "binary": str(binary), "image": image.name,
                  "expected": args.expected, "answer": answer, "passed": passed,
                  "seconds": round(time.monotonic() - started, 2), "exit_code": run.returncode,
                  "stdout": run.stdout, "raw_model_output": run.stderr}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(f"{'PASS' if passed else 'FAIL'}: packaged OCR → AI with denied network: {answer!r}")
        if not passed:
            print(run.stderr, file=sys.stderr)
        raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
