#!/usr/bin/env python3
"""Evaluate arbitrary receipt cases through the production OCR and local model.
Expected answers are used only for judging, never sent to the model.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

MARKER = "AI 답변 · 원문과 대조해 주세요\n\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", nargs=2, action="append", required=True, metavar=("IMAGE", "EXPECTED"))
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--binary", default=".build/debug/OfflineLens")
    parser.add_argument("--output", type=Path, default=Path(".local-ai/receipt-cases.json"))
    args = parser.parse_args()
    if args.iterations < 1:
        parser.error("iterations must be positive")
    manifest = json.loads(Path('.local-ai/manifest.json').read_text())
    binary_sha = hashlib.sha256(Path(args.binary).read_bytes()).hexdigest()
    report = {"model": manifest["model"], "model_revision": manifest.get("model_revision"),
              "model_files": manifest.get("model_files"), "binary": args.binary, "binary_sha256": binary_sha,
              "method": "Apple Vision OCR -> receipt reconstruction -> production LocalModel, --model-only",
              "records": []}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    for case_number, (filename, expected) in enumerate(args.case, 1):
        image = Path(filename).resolve()
        if not image.is_file():
            raise FileNotFoundError(image)
        for iteration in range(1, args.iterations + 1):
            if hashlib.sha256(Path(args.binary).read_bytes()).hexdigest() != binary_sha:
                raise RuntimeError("Binary changed during evaluation; restart with a fixed binary")
            started = time.monotonic()
            result = subprocess.run([args.binary, "--check-image", str(image), "--model-only", "--trace-model"],
                                    capture_output=True, text=True, timeout=75)
            answer = result.stdout.split(MARKER, 1)[1].split("총 소요:", 1)[0].strip() if MARKER in result.stdout else ""
            canonical = re.sub(r"^(?:정답|답|answer)\s*[:：]\s*", "", answer, flags=re.I)
            canonical = re.sub(r"\s+", "", canonical)
            passed = result.returncode == 0 and canonical.lower() == expected.lower()
            record = {"case": case_number, "image": image.name, "iteration": iteration,
                      "expected": expected, "answer": answer, "passed": passed,
                      "seconds": round(time.monotonic() - started, 2), "exit_code": result.returncode,
                      "raw_model_output": result.stderr, "stdout": result.stdout}
            report["records"].append(record)
            args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
            print(f"Image {case_number}, run {iteration}: {'PASS' if passed else 'FAIL'} | expected={expected} | answer={answer!r} | {record['seconds']}s", flush=True)
    passed = sum(r['passed'] for r in report['records'])
    print(f"Result: {passed}/{len(report['records'])}", flush=True)
    raise SystemExit(0 if passed == len(report['records']) else 1)


if __name__ == "__main__":
    main()
