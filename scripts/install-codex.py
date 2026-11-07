#!/usr/bin/env python3
"""Connect an MCP-capable local Genesis service to Codex using a private plugin."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def validate_url(url):
    parsed = urlsplit(url)
    if (parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
            or parsed.username or parsed.password or parsed.path != "/mcp"
            or parsed.query or parsed.fragment):
        raise ValueError("Use the local Genesis HTTP endpoint, e.g. http://127.0.0.1:9999/mcp")
    _ = parsed.port  # Validate an explicitly supplied port.
    return url


def default_config_dir():
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/genesis"
    if os.name == "nt":
        return Path(os.environ.get("APPDATA", str(Path.home()))) / "genesis"
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "genesis"


def ensure_token(config_dir):
    config_dir.mkdir(parents=True, exist_ok=True)
    path = config_dir / "mcp-token"
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        token = path.read_text().strip()
        if len(token) < 32 or any(ch.isspace() for ch in token):
            raise ValueError("Existing mcp-token is invalid; replace it with a private random token of at least 32 characters.")
        path.chmod(0o600)
        return token
    with os.fdopen(fd, "w") as stream:
        token = secrets.token_urlsafe(32)
        stream.write(token + "\n")
    return token


def rpc(url, token, method, params=None):
    message = {"jsonrpc": "2.0", "method": method, "params": params or {}}
    if not method.startswith("notifications/"):
        message["id"] = 1
    body = json.dumps(message).encode()
    req = Request(url, body, headers={"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                                     "Authorization": "Bearer " + token, "MCP-Protocol-Version": "2025-11-25"})
    # Never send this local credential through a proxy or HTTP redirect.
    with build_opener(ProxyHandler({}), NoRedirect()).open(req, timeout=15) as response:
        if response.status == 202:
            return {}
        result = json.load(response)
    if "error" in result:
        raise ValueError("Genesis MCP rejected the request: " + str(result["error"].get("message", "unknown error")))
    return result


def verify_server(url, token):
    initialized = rpc(url, token, "initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                                               "clientInfo": {"name": "genesis-installer", "version": "0.4.0"}})
    if initialized.get("result", {}).get("serverInfo", {}).get("name") != "genesis":
        raise ValueError("This endpoint is not a Genesis MCP server. Install a Genesis release containing MCP support.")
    rpc(url, token, "notifications/initialized")
    names = {tool["name"] for tool in rpc(url, token, "tools/list").get("result", {}).get("tools", [])}
    required = {"genesis_check", "genesis_start_task", "genesis_get_task", "genesis_list_tasks", "genesis_cancel_task", "genesis_list_models", "genesis_get_result", "genesis_send_message", "genesis_reload_config"}
    if not required <= names:
        raise ValueError("Genesis MCP is missing required development tools; update the running release.")
    return rpc(url, token, "tools/call", {"name": "genesis_check", "arguments": {}})["result"]["structuredContent"]


def write_private_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Create without a world-readable window, including when replacing a file.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def prepare_plugin(config_dir, source, url, token):
    marketplace = config_dir / "codex"
    marketplace.mkdir(parents=True, exist_ok=True)
    marketplace.chmod(0o700)
    plugin = marketplace / "plugins/genesis"
    shutil.copytree(source, plugin, dirs_exist_ok=True)
    write_private_json(plugin / "skills/genesis/references/installation.json", {
        "source_root": str(Path(__file__).resolve().parents[1]), "mcp_url": url,
        "config_dir": str(config_dir), "setup_script": "scripts/setup-codex.py"
    })
    write_private_json(plugin / ".mcp.json", {"mcpServers": {"genesis": {
        "type": "http", "url": url, "http_headers": {"Authorization": "Bearer " + token}}}})
    write_private_json(marketplace / ".agents/plugins/marketplace.json", {
        "name": "genesis-mcp-local", "interface": {"displayName": "Genesis MCP"},
        "plugins": [{"name": "genesis", "source": {"source": "local", "path": "./plugins/genesis"},
                     "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}, "category": "Coding"}]})
    return marketplace


def connect(url, config_dir, codex_home=None, output=None):
    config_dir = config_dir.expanduser().resolve()
    url = validate_url(url)
    codex = shutil.which("codex")
    if not codex:
        raise ValueError("Install Codex CLI before connecting Genesis.")
    token = ensure_token(config_dir)
    status = verify_server(url, token)
    source = Path(__file__).resolve().parents[1] / "plugins/genesis"
    marketplace = prepare_plugin(config_dir, source, url, token)
    env = os.environ.copy()
    if codex_home:
        codex_home = codex_home.expanduser().resolve()
        codex_home.mkdir(parents=True, exist_ok=True, mode=0o700)
        env["CODEX_HOME"] = str(codex_home)
    subprocess.run([codex, "plugin", "marketplace", "add", str(marketplace)], env=env, check=True, stdout=output, stderr=output)
    subprocess.run([codex, "plugin", "add", "genesis@genesis-mcp-local"], env=env, check=True, stdout=output, stderr=output)
    return status


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:9999/mcp")
    parser.add_argument("--config-dir", type=Path, default=default_config_dir(), help="Genesis configuration directory used by the running server")
    parser.add_argument("--codex-home", type=Path, help="Optional isolated Codex configuration directory")
    args = parser.parse_args(argv)
    status = connect(args.url, args.config_dir, args.codex_home)
    print("Genesis plugin installed. Open a new Codex session and ask: Use Genesis to develop ...")
    if not status.get("model_ready"):
        print("Genesis models still need configuration. Follow the Skill's references/configuration.md using genesis_check.config_files, then call genesis_reload_config.")
        for warning in status.get("warnings", []):
            print("  " + warning)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, URLError, subprocess.CalledProcessError) as error:
        if isinstance(error, HTTPError):
            message = f"Genesis MCP returned HTTP {error.code}; check the running release, port and --config-dir."
        else:
            message = str(error)
        print("Setup failed: " + message, file=sys.stderr)
        sys.exit(1)
