#!/usr/bin/env python3
"""One-time, checksum-verified installation. The app never downloads models."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent / ".local-ai"
MODEL = "qwen2.5-0.5b-instruct-q2_k.gguf"
MODEL_REVISION = "9217f5db79a29953eb74d5343926648285ec7e67"
MODEL_SHA = "9ee36184e616dfc76df4f5dd66f908dbde6979524ae36e6cefb67f532f798cb8"
RUNTIME_VERSION = "b11284"
RUNTIME_SHA = "f26782642b52467e1c1f7814349c478d5477d61887aeb237b7fe1ee1527554e5"


def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def download(url, path, expected):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and digest(path) == expected:
        print(f"Verified: {path.name}", flush=True)
        return
    partial = path.with_suffix(path.suffix + ".partial")
    print(f"Downloading: {path.name}", flush=True)
    with urllib.request.urlopen(url, timeout=60) as source, partial.open("wb") as target:
        shutil.copyfileobj(source, target, length=1024 * 1024)
    if digest(partial) != expected:
        raise RuntimeError(f"Checksum mismatch: {path.name}")
    partial.replace(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", choices=["qwen2.5-q2", "qwen3-q8", "qwen2.5-1.5b-q4", "qwen2.5-3b-q4", "qwen2.5-7b-q4", "qwen3-1.7b-q8", "qwen3-vl-2b-q4", "qwen3-4b-2507-q3", "qwen3-4b-2507-q4", "exaone-2.4b-q4", "qwen3-4b-thinking-q4", "exaone-2.4b-q6"], default="qwen2.5-7b-q4")
    parser.add_argument("--download-only", action="store_true", help="Download verified model files without changing the selected model")
    args = parser.parse_args()
    name, revision, expected, repo = MODEL, MODEL_REVISION, MODEL_SHA, "Qwen/Qwen2.5-0.5B-Instruct-GGUF"
    if args.model == "qwen3-q8":
        name = "Qwen3-0.6B-Q8_0.gguf"
        revision = "23749fefcc72300e3a2ad315e1317431b06b590a"
        expected = "9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031"
        repo = "Qwen/Qwen3-0.6B-GGUF"
    if args.model == "qwen2.5-1.5b-q4":
        name = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
        revision = "91cad51170dc346986eccefdc2dd33a9da36ead9"
        expected = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
        repo = "Qwen/Qwen2.5-1.5B-Instruct-GGUF"
    if args.model == "qwen2.5-3b-q4":
        name = "qwen2.5-3b-instruct-q4_k_m.gguf"
        revision = "7dabda4d13d513e3e842b20f0d435c732f172cbe"
        expected = "626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d"
        repo = "Qwen/Qwen2.5-3B-Instruct-GGUF"
    if args.model == "qwen3-1.7b-q8":
        name = "Qwen3-1.7B-Q8_0.gguf"
        revision = "90862c4b9d2787eaed51d12237eafdfe7c5f6077"
        expected = "061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a"
        repo = "Qwen/Qwen3-1.7B-GGUF"
    extra_models = []
    if args.model == "qwen2.5-7b-q4":
        name = "qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf"
        revision = "bb5d59e06d9551d752d08b292a50eb208b07ab1f"
        expected = "dfce12e3862a5283ccfb88221b48480e58745165de856439950d0f22590580db"
        repo = "Qwen/Qwen2.5-7B-Instruct-GGUF"
        extra_models = [("qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf", "539cf93f78e887edea1c04e2d7d8cdaca9d01dae9c9025bcb8accbe29df3d72a")]
    if args.model == "qwen3-vl-2b-q4":
        name = "Qwen3-VL-2B-Instruct-Q4_K_M.gguf"
        revision = "8dcb98e52a1d1d02dce9249e5ab15bae8121c666"
        expected = "858fcf2a39dc73b26dd86592cb0a5f949b59d1edb365d1dea98e46b02e955e56"
        repo = "unsloth/Qwen3-VL-2B-Instruct-GGUF"
        extra_models = [("mmproj-F16.gguf", "cd5a851d3928697fa1bd76d459d2cc409b6cf40c9d9682b2f5c8e7c6a9f9630f")]
    if args.model in {"qwen3-4b-2507-q3", "qwen3-4b-2507-q4"}:
        name = "Qwen3-4B-Instruct-2507-Q3_K_M.gguf"
        expected = "9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9"
        if args.model.endswith("q4"):
            name = "Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
            expected = "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597"
        revision = "a06e946bb6b655725eafa393f4a9745d460374c9"
        repo = "unsloth/Qwen3-4B-Instruct-2507-GGUF"
        extra_models = []
    if args.model == "exaone-2.4b-q4":
        name = "EXAONE-3.5-2.4B-Instruct-Q4_K_M.gguf"
        revision = "142acae803a41c206e8d0fa978c6102c748911bb"
        expected = "1660a3794acc33437137faab5cb3fb2b2c4191d0a4ec991d4c31a7197cb2cdbf"
        repo = "LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct-GGUF"
        extra_models = []
    if args.model == "qwen3-4b-thinking-q4":
        name = "Qwen3-4B-Thinking-2507-Q4_K_M.gguf"
        expected = "ddd52e18200baab281c5c46f70d544ce4d4fe4846eab1608f2fff48a64554212"
        revision = "f40adb104d4d44aee52f398b60597c5866a973a3"
        repo = "unsloth/Qwen3-4B-Thinking-2507-GGUF"
        extra_models = []
    if args.model == "exaone-2.4b-q6":
        name = "EXAONE-3.5-2.4B-Instruct-Q6_K.gguf"
        revision = "142acae803a41c206e8d0fa978c6102c748911bb"
        expected = "a1c394dffe188536b286397c4c6853db04386775e35cfbb5ed7179aed8e16e90"
        repo = "LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct-GGUF"
        extra_models = []
    model_name = name
    model = ROOT / "models" / model_name
    archive = ROOT / "runtime.tar.gz"
    download(f"https://huggingface.co/{repo}/resolve/{revision}/{name}", model, expected)
    model_files = [{"name": model_name, "sha256": expected, "bytes": model.stat().st_size}]
    for extra_name, extra_sha in extra_models:
        extra_path = ROOT / "models" / extra_name
        download(f"https://huggingface.co/{repo}/resolve/{revision}/{extra_name}", extra_path, extra_sha)
        model_files.append({"name": extra_name, "sha256": extra_sha, "bytes": extra_path.stat().st_size})
    if args.download_only:
        print("Candidate downloaded; selected model unchanged.", flush=True)
        return
    download(f"https://github.com/ggml-org/llama.cpp/releases/download/{RUNTIME_VERSION}/llama-{RUNTIME_VERSION}-bin-macos-arm64.tar.gz", archive, RUNTIME_SHA)
    runtime = ROOT / "runtime"
    runtime.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            name = Path(member.name).name
            if name not in {"llama-completion", "llama-mtmd-cli", "LICENSE"} and not name.endswith(".dylib"):
                continue
            destination = runtime / name
            if member.isfile():
                with tar.extractfile(member) as source, destination.open("wb") as target:
                    shutil.copyfileobj(source, target)
                destination.chmod(0o755 if name in {"llama-completion", "llama-mtmd-cli"} else 0o644)
            elif member.issym():
                # Only same-directory dylib aliases from the verified archive.
                target = Path(member.linkname)
                if target.name != member.linkname or not target.name.endswith(".dylib"):
                    raise RuntimeError("Unexpected archive link")
                if not destination.exists() and not destination.is_symlink():
                    destination.symlink_to(member.linkname)
    config = {"model": model_name, "model_revision": revision, "model_sha256": expected,
              "model_bytes": model.stat().st_size, "model_files": model_files, "runtime": RUNTIME_VERSION, "runtime_sha256": RUNTIME_SHA}
    if args.model == "qwen3-vl-2b-q4":
        config.update(runner="llama-mtmd-cli", projector="mmproj-F16.gguf")
    (ROOT / "manifest.json").write_text(json.dumps(config, indent=2) + "\n")
    print("Local AI installed. Run: sh scripts/build.sh", flush=True)


if __name__ == "__main__":
    main()
