#!/usr/bin/env python3
"""Platform routing of the shared setup entry, without launching a service."""
import importlib.util
from pathlib import Path
import socket
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("setup", Path(__file__).with_name("setup-codex.py"))
setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(setup)


class PlatformSetupTests(unittest.TestCase):
    def test_closed_loopback_endpoint_is_detected_without_a_probe_timeout(self):
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            probe.listen(1)
            port = probe.getsockname()[1]
            self.assertTrue(setup.endpoint_listening(f'http://127.0.0.1:{port}/mcp'))
        self.assertFalse(setup.endpoint_listening(f'http://127.0.0.1:{port}/mcp'))

    def test_probe_timeout_is_inconclusive_and_never_claims_the_endpoint_stopped(self):
        with patch.object(setup.socket, 'create_connection', side_effect=TimeoutError('timed out')):
            self.assertTrue(setup.endpoint_listening('http://127.0.0.1:9999/mcp'))

    def test_failed_windows_candidate_can_be_cleaned_up_after_its_host_already_exited(self):
        with tempfile.TemporaryDirectory() as root:
            release = Path(root).resolve()
            args = SimpleNamespace(release_dir=release)
            record = {'url':'http://127.0.0.1:9999/mcp', 'release_dir':str(release),
                      'launcher':str(release/'genesis-desktop.exe'), 'runtime_process':{'pid':123456}}
            with patch.object(setup,'IS_WINDOWS',True), patch.object(setup.subprocess,'run',return_value=SimpleNamespace(stdout='')), patch.object(setup,'endpoint_listening',return_value=False), patch.object(setup.os,'kill') as kill:
                setup.stop_owned(args,record['url'],'fixture-token',record,require_idle=False)
                kill.assert_not_called()

    def test_windows_reuses_the_existing_headless_desktop_host(self):
        with tempfile.TemporaryDirectory() as root, patch.object(setup, "IS_WINDOWS", True, create=True):
            release = Path(root)
            launcher = release / "genesis-desktop.exe"
            launcher.write_text("fixture host")
            launcher.chmod(0o755)
            args = SimpleNamespace(server_command=None, method="auto", release_dir=release)
            with patch.object(setup.shutil, "which", return_value=None):
                self.assertEqual(setup.choose_launcher(args), launcher)

    def test_windows_url_discovery_does_not_start_an_exe_as_a_posix_cli(self):
        args = SimpleNamespace(url=None, server_command="genesis-desktop.exe")
        with patch.object(setup, "IS_WINDOWS", True, create=True), patch.object(setup.subprocess, "run", side_effect=AssertionError("unexpected process")):
            self.assertEqual(setup.selected_url(args), "http://127.0.0.1:9999/mcp")


if __name__ == "__main__":
    unittest.main()
