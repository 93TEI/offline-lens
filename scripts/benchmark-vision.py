#!/usr/bin/env python3
"""Test image-only reasoning. No OCR text, rule answers or expected-answer prompts."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time

PROMPT = "Read the receipt and the question printed in this image. Ignore any answer already typed in the input box. Answer the printed question using the receipt. Return only the final number and unit. For a weight question include kg; for a count question include 개. Do not give an explanation."


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("weight_image", type=Path)
    parser.add_argument("count_image", type=Path)
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--output", type=Path, default=Path(".local-ai/vision-benchmark.json"))
    args = parser.parse_args()
    root = Path(".local-ai")
    manifest = json.loads((root / "manifest.json").read_text())
    records = []
    for label, image in [("weight", args.weight_image), ("count", args.count_image)]:
        for iteration in range(args.iterations):
            started = time.monotonic()
            command = [str(root / "runtime" / "llama-mtmd-cli"), "--model", str(root / "models" / manifest["model"]),
                       "--mmproj", str(root / "models" / manifest["projector"]), "--image", str(image.resolve()),
                       "--prompt", PROMPT, "--offline", "--threads", "2", "--threads-batch", "2",
                       "--ctx-size", "4096", "--predict", "128", "--temp", "0", "--seed", "42",
                       "--n-gpu-layers", "0", "--device", "none", "--no-mmproj-offload", "--no-kv-offload",
                       "--no-op-offload", "--image-max-tokens", "768", "--no-warmup"]
            result = subprocess.run(command, capture_output=True, text=True, timeout=180)
            answer = result.stdout.strip()
            answer = re.sub(r"^(kg|개)\s*(\d+(?:\.\d+)?)$", r"\2\1", answer)
            expected = r"3\s*kg" if label == "weight" else r"4\s*개"
            passed = result.returncode == 0 and re.fullmatch(expected, answer, re.I) is not None
            record = {"task": label, "iteration": iteration + 1, "passed": passed,
                      "seconds": round(time.monotonic() - started, 2), "answer": answer,
                      "stdout": result.stdout, "stderr": result.stderr, "exit_code": result.returncode}
            records.append(record)
            args.output.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n")
            print(f"{label} {iteration + 1}: {'PASS' if passed else 'FAIL'} ({record['seconds']}s)\n{answer}", flush=True)
    raise SystemExit(0 if all(r["passed"] for r in records) else 1)


if __name__ == "__main__":
    main()
