#!/usr/bin/env python3
"""Check production prompt branches, uncertain OCR rejection and cancellation."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, default=Path("dist/Offline Lens.app/Contents/MacOS/OfflineLens"))
    parser.add_argument("--output", type=Path, default=Path(".local-ai/runtime-check.json"))
    parser.add_argument("--only", help="Run only the named case")
    args = parser.parse_args()
    binary = args.binary.resolve()
    passage = "민수는 비가 오는 날 도서관에 갔습니다. 민수는 도서관에서 환경 보호에 관한 책을 읽고, 집으로 돌아와 일회용품 사용을 줄이기로 했습니다."
    cases = [
        ("Korean factual question", passage, "민수는 어디에서 책을 읽었습니까?", "도서관", False, False),
        ("Korean passage summary", passage, "민수가 책을 읽은 뒤 실천하기로 한 일을 한 문장으로 쓰세요.", "일회용품", False, False),
        ("Korean missing evidence", passage, "민수의 나이는 몇 살입니까?", "없", False, False),
        ("Receipt unit price", "품목 수량 합계\n우유 2 4800\n빵 3 4500", "가장 많이 구매한 물건의 1개 가격은?", "1500원", False, False),
        ("Unverified OCR rejection", "영수증 표 확인 필요:\n제품명 가격 개수 총합\n루테인 800 5\n900 1 900", "루테인은 몇 개입니까?", "확실하게 연결하지 못했습니다", True, False),
        ("Model cancellation", passage, "이 지문의 중심 내용은?", "PASS: AI 취소 및 자식 프로세스 종료", False, True),
    ]
    records = []
    if args.only:
        cases = [case for case in cases if case[0] == args.only]
        if not cases:
            parser.error("Unknown case")
    with tempfile.TemporaryDirectory(prefix="offlinelens-runtime-check-") as folder:
        for label, text, question, expected, reject, cancel in cases:
            source = Path(folder) / "input.txt"
            source.write_text(text, encoding="utf-8")
            command = [str(binary), "--check-text", str(source), "--question", question]
            command.append("--trace-model")
            if cancel:
                command.append("--check-cancel")
            started = time.monotonic()
            run = subprocess.run(command, capture_output=True, text=True, timeout=75, cwd=folder)
            output = run.stdout + run.stderr
            passed = (run.returncode == 1 if reject else run.returncode == 0) and expected in output
            if label == "Receipt unit price":
                passed = passed and run.stdout.split("\n\n")[-1].strip() == expected
            record = {"case": label, "passed": passed, "seconds": round(time.monotonic() - started, 2),
                      "exit_code": run.returncode, "stdout": run.stdout, "stderr": run.stderr}
            records.append(record)
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n")
            print(f"{'PASS' if passed else 'FAIL'}: {label} ({record['seconds']}s)", flush=True)
    raise SystemExit(0 if all(record["passed"] for record in records) else 1)


if __name__ == "__main__":
    main()
