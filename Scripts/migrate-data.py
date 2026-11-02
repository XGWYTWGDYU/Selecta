#!/usr/bin/env python3
"""Migrate the first Selecta checkout's OCR installation into normal macOS user directories."""
import json
import os
from pathlib import Path
import shutil
import subprocess


def relocate_links(root, old_root):
    for link in root.rglob("*"):
        if link.is_symlink():
            target = Path(os.readlink(link))
            if target.is_absolute() and target.is_relative_to(old_root):
                relocated = root / target.relative_to(old_root)
                link.unlink()
                link.symlink_to(os.path.relpath(relocated, link.parent))


def main():
    project = Path(__file__).resolve().parent.parent
    support = Path.home() / "Library" / "Application Support" / "Selecta"
    ocr = support / "OCR"
    cache = Path.home() / "Library" / "Caches" / "org.ra055814ae03f470d982b.selecta"
    uv = shutil.which("uv")
    if not uv:
        raise RuntimeError("uv is required to migrate the isolated Python environment")
    env = os.environ.copy()
    env.update(UV_CACHE_DIR=str(cache / "uv"), UV_PYTHON_INSTALL_DIR=str(ocr / "Python"), UV_LINK_MODE="copy")
    support.mkdir(parents=True, exist_ok=True, mode=0o700)
    ocr.mkdir(parents=True, exist_ok=True, mode=0o700)
    cache.mkdir(parents=True, exist_ok=True, mode=0o700)

    old_environment = project / ".venv"
    requirements = ocr / "requirements.lock"
    if (old_environment / "bin" / "python").exists():
        frozen = subprocess.check_output([uv, "pip", "freeze", "--python", str(old_environment / "bin" / "python")], env=env)
        requirements.write_bytes(frozen)
    elif not requirements.exists():
        shutil.copy2(project / "requirements-ocr.lock", requirements)

    # Keep the old environment intact until the relocated installation has been verified.
    for source, destination in [(project / ".cache" / "python", ocr / "Python"), (project / ".models", ocr / "Models")]:
        if source.is_dir() and not destination.exists():
            shutil.copytree(source, destination, symlinks=True)
    relocate_links(ocr / "Python", project / ".cache" / "python")
    for name in ("uv", "huggingface"):
        source = project / ".cache" / name
        if source.is_dir():
            shutil.copytree(source, cache / name, symlinks=True, dirs_exist_ok=True)
        relocate_links(cache / name, source)

    interpreters = sorted({p.resolve() for p in (ocr / "Python").glob("cpython-3.12*/bin/python3.12")})
    if not interpreters:
        raise RuntimeError("The existing CPython 3.12 installation was not found")
    environment = ocr / "Environment"
    if not (environment / "bin" / "python").exists():
        subprocess.run([uv, "venv", "--python", str(interpreters[0]), str(environment)], env=env, check=True)
    subprocess.run([uv, "pip", "install", "--offline", "--python", str(environment / "bin" / "python"), "-r", str(requirements)], env=env, check=True)
    subprocess.run([str(environment / "bin" / "python"), "-c", "import sys,paddle,paddleocr; print('Relocated OCR environment:',sys.prefix)"], env=env, check=True)

    # CFPreferences updates preserve all other settings and never touch Keychain credentials.
    for key, old, new in [("pythonPath", old_environment / "bin" / "python", environment / "bin" / "python"), ("paddleModelPath", project / ".models", ocr / "Models")]:
        current = subprocess.run(["defaults", "read", "org.ra055814ae03f470d982b.selecta", key], capture_output=True, text=True)
        if current.returncode != 0 or current.stdout.strip() in ("", str(old)):
            subprocess.run(["defaults", "write", "org.ra055814ae03f470d982b.selecta", key, "-string", str(new)], check=True)
    (support / "migration.json").write_text(json.dumps({"source": str(project), "environment": str(environment), "models": str(ocr / "Models"), "completed": True}, indent=2) + "\n")
    print("Migrated OCR installation:", ocr)
    print("Download caches:", cache)
    print("Original checkout data retained until final verification and cleanup.")


if __name__ == "__main__":
    main()
