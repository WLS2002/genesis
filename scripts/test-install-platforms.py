#!/usr/bin/env python3
"""Install a verified archive through the real POSIX installer and local HTTP."""
import functools
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import threading
import unittest

INSTALL = Path(__file__).with_name("install.sh").resolve()


@unittest.skipIf(os.name == "nt", "POSIX installer; Windows uses portable ZIP")
class PlatformInstallTests(unittest.TestCase):
    def test_intel_mac_can_install_the_matching_verified_server(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            asset = root / "genesis_server_darwin_x64.tar.xz"
            with tarfile.open(asset, "w:xz") as archive:
                for name in ["genesis_server", "genesis"]:
                    contents = b"#!/bin/sh\nexit 0\n"
                    entry = tarfile.TarInfo("genesis_server/bin/" + name)
                    entry.size, entry.mode = len(contents), 0o755
                    archive.addfile(entry, io.BytesIO(contents))
            asset.with_name(asset.name + ".sha256").write_text(hashlib.sha256(asset.read_bytes()).hexdigest())
            shim = root / "bin"
            shim.mkdir()
            (shim / "uname").write_text('#!/bin/sh\ncase "$1" in -s) echo Darwin;; -m) echo x86_64;; esac\n')
            (shim / "uname").chmod(0o755)
            server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(SimpleHTTPRequestHandler, directory=str(root)))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                env = {**os.environ, "PATH": str(shim) + os.pathsep + os.environ["PATH"], "HOME": str(root / "home"),
                       "GENESIS_VERSION": "latest", "GENESIS_DOWNLOAD_BASE": f"http://127.0.0.1:{server.server_port}"}
                result = subprocess.run(["sh", str(INSTALL), "--dir", str(root / "Runtime 测试")], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Checksum verified", result.stdout)
                self.assertTrue((root / "Runtime 测试/bin/genesis").is_file())
            finally:
                server.shutdown()
                server.server_close()
                thread.join()


if __name__ == "__main__":
    unittest.main()
