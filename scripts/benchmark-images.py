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
    args = parser.parse_args()
    records = []
    for label, image in [("weight", args.weight_image), ("count", args.count_image)]:
        for index in range(args.iterations):
            started = time.monotonic()
            result = subprocess.run([args.binary, "--check-image", str(image.resolve()), "--model-only"],
                                    capture_output=True, text=True, timeout=75)
            answer = result.stdout.split("AI 답변 · 원문과 대조해 주세요\n\n")[-1].split("총 소요:")[0].strip()
            first = answer.splitlines()[0] if answer else ""
            if label == "weight":
                passed = re.search(r"(?<![\d.])3\s*(?:kg|kilograms?|킬로그램)(?![A-Za-z])", first, re.I) is not None
            else:
                # Judge the answer before the explanation, not digits in OCR.
                passed = re.search(r"(?<![\d.])4\s*(?:개|items?|objects?|$)", first, re.I) is not None
            passed = passed and result.returncode == 0
            record = {"task": label, "iteration": index + 1, "passed": passed, "seconds": round(time.monotonic() - started, 2),
                      "answer": answer, "stdout": result.stdout, "stderr": result.stderr, "exit_code": result.returncode}
            records.append(record)
            print(f"{label} {index + 1}: {'PASS' if passed else 'FAIL'} ({record['seconds']}s)\n{answer}", flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n")
    print(f"Result: {sum(r['passed'] for r in records)}/{len(records)}", flush=True)
    raise SystemExit(0 if all(r["passed"] for r in records) else 1)


if __name__ == "__main__":
    main()
