#!/usr/bin/env python3
"""Portable ZIP installation tests; no Windows runtime or model required."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SPEC = importlib.util.spec_from_file_location("windows", Path(__file__).with_name("install-windows.py"))
windows = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(windows)


class WindowsInstallTests(unittest.TestCase):
    def package(self):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            archive.writestr("genesis-desktop.exe", "fixture launcher")
            archive.writestr("resources/genesis-backend/bin/genesis_desktop.bat", "fixture backend")
        body = stream.getvalue()
        return body, (hashlib.sha256(body).hexdigest() + "  genesis_desktop_windows_x64.zip\n").encode()

    def test_installs_verified_portable_package_with_spaces_and_unicode(self):
        body, checksum = self.package()
        with tempfile.TemporaryDirectory() as root, patch.object(windows, "download", side_effect=[checksum, body]):
            dest = Path(root) / "Genesis 测试 runtime"
            launcher = windows.install(dest)
            self.assertEqual(launcher, dest / "genesis-desktop.exe")
            self.assertEqual(launcher.read_text(), "fixture launcher")

    def test_bad_checksum_keeps_existing_runtime(self):
        body, _ = self.package()
        with tempfile.TemporaryDirectory() as root, patch.object(windows, "download", side_effect=[b"0"*64, body]):
            dest = Path(root) / "runtime"
            dest.mkdir()
            (dest / "genesis-desktop.exe").write_text("old runtime")
            with self.assertRaisesRegex(ValueError, "checksum"):
                windows.install(dest)
            self.assertEqual((dest / "genesis-desktop.exe").read_text(), "old runtime")

    def test_never_overwrites_an_unrelated_directory(self):
        with tempfile.TemporaryDirectory() as root:
            dest = Path(root) / "my files"
            dest.mkdir()
            (dest / "keep.txt").write_text("user work")
            with self.assertRaisesRegex(ValueError, "Genesis"):
                windows.install(dest)
            self.assertEqual((dest / "keep.txt").read_text(), "user work")

    def test_rejects_zip_without_backend_and_preserves_old_runtime(self):
        body = io.BytesIO()
        with zipfile.ZipFile(body, "w") as archive:
            archive.writestr("genesis-desktop.exe", "incomplete")
        package = body.getvalue()
        checksum = hashlib.sha256(package).hexdigest().encode()
        with tempfile.TemporaryDirectory() as root, patch.object(windows, "download", side_effect=[checksum, package]):
            dest = Path(root) / "runtime"
            dest.mkdir()
            (dest / "genesis-desktop.exe").write_text("old runtime")
            with self.assertRaisesRegex(ValueError, "backend"):
                windows.install(dest)
            self.assertEqual((dest / "genesis-desktop.exe").read_text(), "old runtime")


if __name__ == "__main__":
    unittest.main()
