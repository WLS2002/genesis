#!/usr/bin/env python3
"""Behavioral tests for the local Codex installer (no live model required)."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("install_codex", Path(__file__).with_name("install-codex.py"))
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def test_only_local_http_endpoint_is_accepted(self):
        for url in ["http://example.com/mcp", "http://127.0.0.1:9999/mcp?token=x", "http://u:p@localhost/mcp", "file:///tmp/mcp", "http://127.0.0.1/api"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                installer.validate_url(url)
        self.assertEqual(installer.validate_url("http://127.0.0.1:9999/mcp"), "http://127.0.0.1:9999/mcp")

    def test_rerun_preserves_token_and_model_configuration(self):
        with tempfile.TemporaryDirectory() as root:
            config = Path(root)
            model = config / "config.toml"
            model.write_text("existing model config")
            first = installer.ensure_token(config)
            second = installer.ensure_token(config)
            self.assertEqual(first, second)
            self.assertGreaterEqual(len(first), 32)
            self.assertEqual((config / "mcp-token").stat().st_mode & 0o777, 0o600)
            self.assertEqual(model.read_text(), "existing model config")

    def test_private_plugin_contains_persistent_connection_and_skill(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(__file__).resolve().parents[1] / "plugins" / "genesis"
            config = Path(root)
            token = installer.ensure_token(config)
            marketplace = installer.prepare_plugin(config, source, "http://localhost:9999/mcp", token)
            plugin = marketplace / "plugins" / "genesis"
            mcp = json.loads((plugin / ".mcp.json").read_text())
            self.assertEqual(mcp["mcpServers"]["genesis"]["http_headers"]["Authorization"], "Bearer " + token)
            self.assertEqual(mcp["mcpServers"]["genesis"]["url"], "http://localhost:9999/mcp")
            self.assertEqual((plugin / ".mcp.json").stat().st_mode & 0o777, 0o600)
            self.assertTrue((plugin / "skills" / "genesis" / "SKILL.md").is_file())
            manifest = json.loads((marketplace / ".agents/plugins/marketplace.json").read_text())
            self.assertEqual(manifest["plugins"][0]["source"]["path"], "./plugins/genesis")

    def test_rejects_server_that_does_not_offer_genesis_tools(self):
        with patch.object(installer, "rpc", side_effect=[{"result": {"protocolVersion": "2025-11-25", "serverInfo": {"name": "other"}}}]):
            with self.assertRaisesRegex(ValueError, "Genesis"):
                installer.verify_server("http://localhost:9999/mcp", "token")


if __name__ == "__main__":
    unittest.main()
