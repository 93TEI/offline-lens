#!/usr/bin/env python3
"""One-time, checksum-verified installation. The app never downloads models."""
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
    model = ROOT / "models" / MODEL
    archive = ROOT / "runtime.tar.gz"
    download(f"https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/{MODEL_REVISION}/{MODEL}", model, MODEL_SHA)
    download(f"https://github.com/ggml-org/llama.cpp/releases/download/{RUNTIME_VERSION}/llama-{RUNTIME_VERSION}-bin-macos-arm64.tar.gz", archive, RUNTIME_SHA)
    runtime = ROOT / "runtime"
    runtime.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            name = Path(member.name).name
            if name not in {"llama-completion", "LICENSE"} and not name.endswith(".dylib"):
                continue
            destination = runtime / name
            if member.isfile():
                with tar.extractfile(member) as source, destination.open("wb") as target:
                    shutil.copyfileobj(source, target)
                destination.chmod(0o755 if name == "llama-completion" else 0o644)
            elif member.issym():
                # Only same-directory dylib aliases from the verified archive.
                target = Path(member.linkname)
                if target.name != member.linkname or not target.name.endswith(".dylib"):
                    raise RuntimeError("Unexpected archive link")
                if not destination.exists() and not destination.is_symlink():
                    destination.symlink_to(member.linkname)
    config = {"model": MODEL, "model_revision": MODEL_REVISION, "model_sha256": MODEL_SHA,
              "model_bytes": model.stat().st_size, "runtime": RUNTIME_VERSION, "runtime_sha256": RUNTIME_SHA}
    (ROOT / "manifest.json").write_text(json.dumps(config, indent=2) + "\n")
    print("Local AI installed. Run: sh scripts/build.sh", flush=True)


if __name__ == "__main__":
    main()
