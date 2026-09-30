# Offline Lens handoff — 2026-10-01

## User’s goal

Finish the local, internet-free problem reader. In particular, read the two receipt screenshots the user supplied, restore rows from separated/torn columns, answer “How many items in total?” and “How many kg is one 묵은지?”, and choose the smallest local model that actually answers both. The user explicitly approved downloading model/runtime files and said to judge the choice by whether it solves these two images. They asked to be consulted about meaningful tradeoffs. They then asked to stop and leave this handoff for the next session.

## Current worktree

Project: this repository. Changes are **uncommitted**. No screenshots were copied into the repository. The public GitHub repository is `93TEI/OfflineLens`; these changes have **not** been pushed.

The code currently adds:

- `Sources/OfflineLensCore/ReceiptLayout.swift`: OCR word boxes, separate-column alignment for torn receipts, and a strict `unit price × quantity = total` check before restoring table rows.
- `Sources/OfflineLens/OCR.swift`: retain Vision locations/confidence, recognize numbers inside OCR lines, grow the decode size to 2,400 px, detect the on-screen question, and supply reconstructed table plus original OCR for review.
- `Sources/OfflineLensCore/Solver.swift`: parse a labelled price/quantity/total table; answer total item count; answer one-item and total kg from weight recorded in a product name; stop receipt parsing before the appended raw OCR.
- `Sources/OfflineLens/main.swift`: auto-fill recognized question, show repaired table/evidence, accept WebP, enable local AI by default when installed, and provide a separate “AI로 풀이” action.
- `Sources/OfflineLens/LocalModel.swift`: locate bundled/local model; run llama.cpp on CPU with offline mode, bounded context/output/time, and pipe the prompt as UTF-8 over stdin. The stdin change addresses a macOS `Process.arguments` Hangul normalization issue discovered during testing.
- `Sources/OfflineLens/ImageCheck.swift`, `scripts/benchmark-images.py`, and `scripts/compare-models.py`: run OCR and either rules or model on an image, judge the two requested answers, and compare candidates. The compare script restores `.local-ai/manifest.json` when it exits normally.
- `scripts/install-local-ai.py` and the app build script: pinned downloads with SHA-256 checks and optional bundling.
- `Tests/OfflineLensCoreTests/ReceiptLayoutTests.swift`: tests receipt columns, row checks, total quantity, kg, and OCR-tail handling.

## Verification already done

- `swift test -j 2`: **10 tests passed**, including the new synthetic geometry and solver tests. Run again after continuing, since later UI/prompt edits were made.
- `swift build -j 2`: passed after the UI changes and after switching model prompts to UTF-8 stdin. A final build after the latest prompt edit still needs confirmation.
- Both user images were processed with Apple Vision. The current column reconstruction produced:
  - First screenshot: `묵은지 3kg | 900 | 7 | 6300`, `블루베리즙 | 700 | 9 | 6300`, `빵가루 | 300 | 8 | 2400`. Price × quantity matches total in all rows. Question: `구매한 묵은지 하나는 몇 kg 입니까?`
  - Second screenshot: rows `(400,2,800)`, `(300,1,300)`, `(800,1,800)`. Price × quantity matches total in all rows. Question: `영수증에서 구매한 물건은 총 몇 개 입니까?`
- The rule solver tests produce **3kg** for the first image’s question, **21kg** for total 묵은지 weight, and **24개** for all first-image items; for the second image it produces **4개**. The user’s first image clearly asks for one 묵은지’s weight, so the earlier conversational answer “27kg” was wrong and has already been corrected to 3kg.
- The small-model investigation is **not complete**. Several early candidate failures are invalid evidence: Swift passed Hangul in argv and llama.cpp received decomposed Jamo. After switching to UTF-8 stdin, later Qwen3 0.6B runs still did not reliably return a clean correct final answer. One reasoning response correctly worked out `2 + 1 + 1 = 4` but repeated `total_price = 1900` until its output limit; a sampled non-thinking response was wrong. Do not describe any model as passing both screenshots yet.

## Downloaded local files (ignored by Git)

`.local-ai/` is gitignored and contains the pinned llama.cpp macOS arm64 `b11284` runtime (`llama-completion`, dylibs, licence), the official Qwen2.5-0.5B Q2/Q4 models, official Qwen3-0.6B Q8, and Qwen3 Q2_K/Q3_K_S quantizations made locally from Q8. The current manifest was restored/set to:

```json
{
  "model": "Qwen3-0.6B-Q8_0.gguf",
  "model_revision": "23749fefcc72300e3a2ad315e1317431b06b590a",
  "model_sha256": "9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031",
  "model_bytes": 639446688,
  "runtime": "b11284",
  "runtime_sha256": "f26782642b52467e1c1f7814349c478d5477d61887aeb237b7fe1ee1527554e5",
  "quantization": "official Q8_0"
}
```

The supplied screenshots were only benchmark inputs and were not committed. The temporary screenshot path may have expired; use the original image attachments again if needed.

## Immediate next steps

1. Inspect `git status`, `LocalModel.swift`, and `.local-ai/manifest.json`. Confirm no model benchmark is still running; the user interrupted the `compare-models.py` run before it produced `comparison.json`.
2. Fix the install/build mismatch before shipping: `install-local-ai.py` currently installs Qwen2.5 Q2 only, while `scripts/build.sh` hardcodes copying that model. These must copy the model filename from the manifest and support the selected Qwen3 candidate. The current Q8 manifest cannot successfully bundle with the hardcoded Q2 copy.
3. Improve the model interaction without putting expected answers into the prompt. The two receipt tasks can be answered deterministically by the new solver; keep “AI로 풀이” as an honest way to test the model. For broader Korean questions, consider a small-model Korean answer check with concise user-facing fallback when it does not answer.
4. Re-run the two-image matrix **after** the UTF-8 stdin fix and latest prompt using `scripts/compare-models.py`. It sorts by model file size and tries the installed Qwen2.5 Q2/Q4 and Qwen3 Q2/Q3/Q8 candidates. Because the generated responses varied and the harness judges first-line answers, inspect every saved JSON before calling a candidate successful. If a candidate works, repeat the two images at least three times using the same production prompt/settings and verify the kg unit is preserved.
5. Harden process cleanup if writing the prompt to stdin throws: close/terminate the child on write error, and ensure the timeout is scheduled before potentially blocking work. Review `--predict 256` against Qwen3 reasoning output and the 60-second limit.
6. Align README with the new installation and bundled model, run the final tests/build/`--check-ocr`, open the rebuilt app, and verify image-open → OCR → auto-question → table-check → solve. Consider a genuinely network-disabled runtime test; current `--offline` is an inference-runtime flag, not an OS sandbox.
7. Only once all checks pass, commit and push the code to `origin/main` (the user earlier asked to publish the repository, but these current edits have not been pushed).

## Useful commands

```sh
cd /path/to/OfflineLens
swift test -j 2
swift build -j 2
python3 scripts/benchmark-images.py <weight-question-image> <count-question-image> --iterations 3
python3 scripts/compare-models.py <weight-question-image> <count-question-image> Qwen3-0.6B-Q2_K.gguf Qwen3-0.6B-Q3_K_S.gguf qwen2.5-0.5b-instruct-q2_k.gguf qwen2.5-0.5b-instruct-q4_0.gguf Qwen3-0.6B-Q8_0.gguf
sh scripts/build.sh
```
