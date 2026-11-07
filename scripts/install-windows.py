#!/usr/bin/env python3
"""Install the portable Windows host; it runs the existing --headless runtime."""
import argparse
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import urlopen
import zipfile

ASSET = "genesis_desktop_windows_x64.zip"


def default_install_dir():
    return Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "Genesis/server"


def download(url):
    with urlopen(url, timeout=120) as response:
        return response.read()


def release_urls():
    version = os.environ.get("GENESIS_VERSION", "latest")
    primary = os.environ.get("GENESIS_DOWNLOAD_BASE", "https://genesis.evox.group/dl").rstrip("/")
    fallback = os.environ.get("GENESIS_DOWNLOAD_FALLBACK_BASE", "https://github.com/EMI-Group/genesis/releases").rstrip("/")
    first = f"{primary}/{ASSET}" if version == "latest" else f"{primary}/{version}/{ASSET}"
    second = f"{fallback}/latest/download/{ASSET}" if version == "latest" else f"{fallback}/download/{version}/{ASSET}"
    return list(dict.fromkeys([first, second]))


def install(destination):
    destination = destination.expanduser().resolve()
    if destination.exists() and any(destination.iterdir()) and not (destination / "genesis-desktop.exe").is_file():
        raise ValueError(f"{destination} is not a Genesis installation; choose another directory.")
    for url in release_urls():
        try:
            checksum = download(url + ".sha256").decode().split()[0]
            package = download(url)
            break
        except URLError:
            continue
    else:
        raise ValueError(f"Cannot download {ASSET} and its checksum. Use a release containing the Windows MCP preview.")
    if hashlib.sha256(package).hexdigest() != checksum:
        raise ValueError(f"Genesis package checksum mismatch: {ASSET}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".genesis-install-", dir=destination.parent) as temporary:
        stage = Path(temporary) / "runtime"
        with zipfile.ZipFile(io.BytesIO(package)) as archive:
            archive.extractall(stage)
        if not (stage / "genesis-desktop.exe").is_file() or not (stage / "resources/genesis-backend/bin/genesis_desktop.bat").is_file():
            raise ValueError("Genesis portable package is missing its launcher or backend.")
        backup = Path(temporary) / "previous"
        if destination.exists():
            destination.rename(backup)
        try:
            stage.rename(destination)
        except OSError:
            if backup.exists():
                backup.rename(destination)
            raise
    return destination / "genesis-desktop.exe"


def start(launcher, url, config_dir, env):
    address = urlsplit(url)
    env = {**env, "PORT": str(address.port or 80), "EVOGIT_BIND": address.hostname}
    config_dir.mkdir(parents=True, exist_ok=True)
    log_path = config_dir / "server.log"
    with log_path.open("ab") as log:
        process = subprocess.Popen([str(launcher), "--headless"], env=env,
            stdin=subprocess.DEVNULL, stdout=log, stderr=log, close_fds=True,
            creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP)
    return {"pid": process.pid, "log": str(log_path)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", type=Path, default=default_install_dir())
    args = parser.parse_args()
    print(install(args.dir))
