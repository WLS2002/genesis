#!/usr/bin/env python3
"""Native package → installer → actual Codex registration → live MCP checks."""
import argparse
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("connector", ROOT / "scripts/install-codex.py")
connector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(connector)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--assets", type=Path, default=Path("dist"))
parser.add_argument("--platform", required=True)
args = parser.parse_args()
server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(SimpleHTTPRequestHandler, directory=str(args.assets.resolve())))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()

with tempfile.TemporaryDirectory(prefix="Genesis smoke 测试 ") as temporary:
    trial = Path(temporary)
    env = {**os.environ, "GENESIS_VERSION": "latest", "GENESIS_DOWNLOAD_BASE": f"http://127.0.0.1:{server.server_port}",
           "CODEX_HOME": str(trial / "codex"), "GENESIS_DATA_DIR": str(trial / "data")}
    if os.name == "nt":
        env["APPDATA"], env["LOCALAPPDATA"] = str(trial / "Roaming"), str(trial / "Local")
        config = Path(env["APPDATA"]) / "genesis"
    elif sys.platform == "darwin":
        config = connector.default_config_dir()
    else:
        env["XDG_CONFIG_HOME"] = str(trial / "config")
        config = Path(env["XDG_CONFIG_HOME"]) / "genesis"
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    url = f"http://127.0.0.1:{port}/mcp"
    runtime = trial / "Runtime 测试"
    result = None
    try:
        run = subprocess.run([sys.executable, str(ROOT / "scripts/setup-codex.py"), "--method", "release", "--json",
            "--url", url, "--release-dir", str(runtime), "--config-dir", str(config), "--codex-home", str(trial / "codex")],
            env=env, capture_output=True, text=True, encoding="utf-8", timeout=180)
        print(run.stderr)
        print(run.stdout)
        assert run.returncode == 2, run.returncode
        result = json.loads(run.stdout)
        assert result["plugin_installed"] and not result["configuration_ready"]
        backend = runtime / "resources/genesis-backend" if os.name == "nt" else runtime
        vendor_names = {"linux_x64": "linux-x86_64", "linux_arm64": "linux-arm64",
            "darwin_x64": "macos-x86_64", "darwin_arm64": "macos-arm64", "windows_x64": "windows-x64"}
        vendor = next(backend.glob("lib/evo_git-*/priv/vendor/" + vendor_names[args.platform]))
        subprocess.run([str(vendor / ("rg.exe" if os.name == "nt" else "rg")), "--version"], check=True)
        if os.name == "nt":
            subprocess.run([str(vendor / "mingit/cmd/git.exe"), "--version"], check=True)
        token = (config / "mcp-token").read_text().strip()
        check = connector.verify_server(url, token)
        assert Path(check["config_files"]["config"]).resolve() == (config / "config.toml").resolve()
        assert Path(check["config_files"]["credentials"]).resolve() == (config / "credentials.toml").resolve()
        (config / "config.toml").write_text('[[llm.models]]\nid = "offline"\nmodel = "openai:offline-fixture"\n', encoding="utf-8")
        (config / "credentials.toml").write_text('OPENAI_API_KEY = "offline-fixture"\n', encoding="utf-8")
        loaded = connector.rpc(url, token, "tools/call", {"name": "genesis_reload_config", "arguments": {}})["result"]
        assert not loaded["isError"] and loaded["structuredContent"]["model_ready"]
        assert loaded["structuredContent"]["configuration_reloaded"]
        models = connector.rpc(url, token, "tools/call", {"name": "genesis_list_models", "arguments": {}})["result"]
        assert models["structuredContent"]["models"][0]["id"] == "offline"
        print(json.dumps({"platform": args.platform, "native_package_install": True,
            "codex_plugin_registration": True, "tools": 9, "file_configuration_reload": True,
            "provider_connection_tested": False}))
    finally:
        if os.name == "nt":
            if result and result.get("runtime_process"):
                # Kill only the existing Rust host; its lifetime pipe closes the BEAM.
                subprocess.run(["taskkill", "/PID", str(result["runtime_process"]["pid"]), "/F"], check=True)
        elif (runtime / "bin/genesis").exists():
            subprocess.run([str(runtime / "bin/genesis"), "stop"], env=env, check=True)
        server.shutdown()
        server.server_close()
        thread.join()
        for _ in range(40):
            with socket.socket() as probe:
                if probe.connect_ex(("127.0.0.1", port)) != 0:
                    break
            time.sleep(.25)
        else:
            raise AssertionError("Backend survived its lifecycle host shutdown")
        for name in ["config.toml", "credentials.toml", "mcp-token"]:
            (config / name).unlink(missing_ok=True)
