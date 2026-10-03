#!/usr/bin/env python3
"""Bundle checksum-verified model files selected in the local manifest."""
import hashlib
import json
from pathlib import Path
import shutil
import sys


def main():
    root = Path(__file__).resolve().parent.parent / ".local-ai"
    destination = Path(sys.argv[1])
    manifest = json.loads((root / "manifest.json").read_text())
    files = manifest.get("model_files", [{"name": manifest["model"],
        "sha256": manifest["model_sha256"], "bytes": manifest["model_bytes"]}])
    names = set()
    for record in files:
        name = record["name"]
        if not isinstance(name, str) or Path(name).name != name or not name.endswith(".gguf") or name in names:
            raise ValueError("Invalid model filename in manifest")
        names.add(name)
        model = root / "models" / name
        sha = hashlib.sha256()
        with model.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                sha.update(chunk)
        if sha.hexdigest() != record["sha256"] or model.stat().st_size != record["bytes"]:
            raise ValueError(f"Model does not match manifest: {name}")
    if manifest["model"] not in names:
        raise ValueError("Selected model is missing from model_files")
    models = destination / "models"
    models.mkdir(parents=True, exist_ok=True)
    for name in names:
        shutil.copy2(root / "models" / name, models / name)
    for old in models.glob("*.gguf"):
        if old.name not in names:
            old.unlink()
    shutil.copy2(root / "manifest.json", destination / "manifest.json")
    print(f"Bundled model: {manifest['model']} ({len(names)} files)")


if __name__ == "__main__":
    main()
