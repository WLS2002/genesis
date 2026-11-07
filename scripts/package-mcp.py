#!/usr/bin/env python3
"""Stage native preview assets using Genesis's existing release layouts."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--platform", required=True)
parser.add_argument("--release-dir", type=Path, required=True)
parser.add_argument("--output", type=Path, default=Path("dist"))
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
if args.platform == "windows_x64":
    asset = args.output / "genesis_desktop_windows_x64.zip"
    with tempfile.TemporaryDirectory() as temporary:
        stage = Path(temporary)
        shutil.copy2("desktop/src-tauri/target/release/genesis-desktop.exe", stage)
        for library in Path("desktop/src-tauri/target/release").glob("*.dll"):
            shutil.copy2(library, stage)
        shutil.copytree(args.release_dir, stage / "resources/genesis-backend")
        with zipfile.ZipFile(asset, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in stage.rglob("*"):
                if path.is_file():
                    archive.write(path, path.relative_to(stage))
else:
    asset = args.output / f"genesis_server_{args.platform}.tar.xz"
    with tarfile.open(asset, "w:xz") as archive:
        archive.add(args.release_dir, arcname="genesis_server")
digest = hashlib.sha256(asset.read_bytes()).hexdigest()
asset.with_name(asset.name + ".sha256").write_text(digest + "  " + asset.name + "\n")
(args.output / f"build-info-{args.platform}.json").write_text(json.dumps({
    "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "platform": args.platform, "build_os": platform.platform(),
    "libc": platform.libc_ver(), "sha256": digest, "asset": asset.name
}, indent=2) + "\n")
print(asset)
