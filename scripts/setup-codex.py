#!/usr/bin/env python3
"""Prepare/reuse Genesis, start it, connect Codex, and report remaining setup work."""
import argparse
import importlib.util
import json
import platform
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import tempfile
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("genesis_connector", ROOT / "scripts/install-codex.py")
connector = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(connector)
_windows_spec = importlib.util.spec_from_file_location("genesis_windows", ROOT / "scripts/install-windows.py")
windows = importlib.util.module_from_spec(_windows_spec)
_windows_spec.loader.exec_module(windows)
IS_WINDOWS = sys.platform == "win32"


class SetupError(Exception):
    def __init__(self, code, message):
        self.code, self.message = code, message
        super().__init__(message)


def run(command, env=None):
    print("Running: " + " ".join(map(str, command)), file=sys.stderr, flush=True)
    subprocess.run(list(map(str, command)), cwd=ROOT, env=env, check=True,
                   stdout=sys.stderr, stderr=sys.stderr)


def source_launcher():
    if IS_WINDOWS:
        raise SetupError("source_toolchain_required", "For native Windows use the portable MCP release, or build the existing desktop host and pass its executable with --server-command. WSL uses the Linux source/release path.")
    if not shutil.which("mix") or not shutil.which("elixir"):
        raise SetupError("source_toolchain_required", "Source builds need Elixir >=1.20.4 and Erlang/OTP29, plus Git. Prepare that toolchain or use an MCP-capable binary release.")
    version = subprocess.run(["elixir", "--version"], capture_output=True, text=True, check=True).stdout
    match = re.search(r"Elixir (\d+)\.(\d+)\.(\d+)", version)
    if not match or tuple(map(int, match.groups())) < (1, 20, 4) or "Erlang/OTP 29" not in version:
        raise SetupError("source_toolchain_required", "This checkout requires Elixir >=1.20.4 and Erlang/OTP29; see README Run from source.")
    if not shutil.which("git"):
        raise SetupError("git_required", "Install Git before building Genesis.")
    build_env = {**os.environ, "MIX_ENV": "prod"}
    for command in [["mix", "deps.get"], ["mix", "assets.deploy"], ["mix", "release", "genesis_server", "--overwrite"]]:
        run(command, build_env)
    from genesis_build import stamp
    target = ('darwin' if sys.platform == 'darwin' else 'linux') + ('_arm64' if platform.machine().lower() in ('arm64','aarch64') else '_x64')
    stamp(ROOT / '_build/prod/rel/genesis_server', target)
    return ROOT / "_build/prod/rel/genesis_server/bin/genesis"


def choose_launcher(args):
    if args.server_command:
        command = Path(args.server_command).expanduser().resolve()
    elif IS_WINDOWS:
        if args.method == "source":
            return source_launcher()
        installed = shutil.which("genesis-desktop")
        if args.method == "auto" and installed:
            command = Path(installed)
        elif args.method == "auto" and (args.release_dir / "genesis-desktop.exe").is_file():
            command = args.release_dir / "genesis-desktop.exe"
        else:
            command = windows.install(args.release_dir)
    elif args.method == "source":
        command = source_launcher()
    elif args.method == "auto" and shutil.which("genesis"):
        command = Path(shutil.which("genesis"))
    elif args.method == "auto" and (args.release_dir / "bin/genesis").is_file():
        command = args.release_dir / "bin/genesis"
    elif args.method == "auto" and (ROOT / "_build/prod/rel/genesis_server/bin/genesis").is_file():
        command = ROOT / "_build/prod/rel/genesis_server/bin/genesis"
    elif args.method == "auto" and shutil.which("mix") and shutil.which("elixir"):
        command = source_launcher()
    else:
        run(["sh", ROOT / "scripts/install.sh", "--dir", args.release_dir])
        command = args.release_dir / "bin/genesis"
    if not command.is_file() or not os.access(command, os.X_OK):
        raise SetupError("launcher_missing", "Genesis lifecycle launcher is missing or not executable: " + str(command))
    return command


def refused(error):
    return isinstance(error, URLError) and isinstance(error.reason, ConnectionRefusedError)


def verify(url, token):
    try:
        return connector.verify_server(url, token)
    except HTTPError as error:
        raise SetupError("incompatible_service", f"The service at {url} returned HTTP {error.code}. Check the URL/config directory or update the running release to one containing MCP support. It has not been restarted or replaced.") from error
    except ValueError as error:
        raise SetupError("incompatible_service", str(error)) from error


def selected_url(args):
    if args.url:
        return connector.validate_url(args.url)
    if IS_WINDOWS:
        return "http://127.0.0.1:9999/mcp"
    command = str(Path(args.server_command).expanduser().resolve()) if args.server_command else shutil.which("genesis")
    if not command and (args.release_dir.expanduser() / "bin/genesis").is_file():
        command = str(args.release_dir.expanduser() / "bin/genesis")
    if not command:
        built = ROOT / "_build/prod/rel/genesis_server/bin/genesis"
        if built.is_file():
            command = str(built)
    if command:
        saved = subprocess.run([str(command), "url"], capture_output=True, text=True, timeout=10)
        if saved.returncode == 0:
            try:
                return connector.validate_url(saved.stdout.strip().rstrip("/") + "/mcp")
            except ValueError:
                pass
    return "http://127.0.0.1:9999/mcp"


def runtime_environment(args):
    env = dict(os.environ)
    if sys.platform.startswith('linux'):
        env['XDG_CONFIG_HOME'] = str(args.config_dir.parent)
    env.setdefault('GENESIS_LINGER', 'no')
    return env


def stop_owned(args, url, token, record, *, require_idle=True):
    if record.get('url') != url or Path(record.get('release_dir', '')).resolve() != args.release_dir:
        raise SetupError('unmanaged_service', 'This endpoint has no matching managed installation record. Inspect and stop the previous host before reinstalling.')
    launcher = Path(record['launcher']).resolve()
    if not launcher.is_relative_to(args.release_dir):
        raise SetupError('unmanaged_service', 'The launcher is outside this managed installation.')
    if require_idle:
        print('Checking Genesis is idle before upgrading.', file=sys.stderr, flush=True)
        for state in ('pending','running','finalizing','cancelling'):
            reply = connector.rpc(url, token, 'tools/call', {'name':'genesis_list_tasks', 'arguments':{'status':state,'limit':1}})['result']
            tasks = reply.get('structuredContent', {})
            if 'tasks' not in tasks or 'total' not in tasks:
                raise SetupError('task_status_unavailable', 'Cannot confirm that the existing service is idle.')
            if tasks['total'] or tasks['tasks']:
                raise SetupError('active_tasks', 'Genesis has active tasks. Finish or stop them through MCP before upgrading.')
    if IS_WINDOWS:
        pid = int(record.get('runtime_process', {}).get('pid', 0))
        if pid <= 0:
            raise SetupError('unmanaged_service', 'Missing Windows host process identity.')
        query = f'(Get-CimInstance Win32_Process -Filter "ProcessId = {pid}").ExecutablePath'
        actual = subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',query], capture_output=True,text=True,check=True).stdout.strip()
        if os.path.normcase(actual) != os.path.normcase(str(launcher)):
            raise SetupError('unmanaged_service', 'The saved Windows process no longer belongs to this installation.')
        print('Stopping the managed Genesis host.', file=sys.stderr, flush=True)
        os.kill(pid, signal.SIGTERM)
    else:
        run([launcher, 'stop'], runtime_environment(args))
    deadline = time.monotonic()+20
    print('Waiting for the previous Genesis endpoint to close.', file=sys.stderr, flush=True)
    while time.monotonic() < deadline:
        if not endpoint_listening(url):
            return
        time.sleep(.1)
    raise SetupError('stop_failed', 'The previous Genesis endpoint is still running; no files were replaced.')


def endpoint_listening(url):
    address = urlsplit(url)
    try:
        # Windows can take longer than one second to report loopback refusal.
        with socket.create_connection((address.hostname, address.port or 80), timeout=5):
            return True
    except ConnectionRefusedError:
        return False
    except TimeoutError:
        # No refusal was observed. Continue the bounded wait rather than
        # claiming shutdown or aborting an otherwise successful stop.
        return True


def upgrade_owned(args, url, token):
    record_path = args.config_dir/'runtime.json'
    if not record_path.is_file():
        raise SetupError('unmanaged_service', 'No runtime.json ownership record exists. Inspect and stop the previous host before reinstalling.')
    record = json.loads(record_path.read_text())
    print('Saving the previous Genesis installation for rollback.', file=sys.stderr, flush=True)
    # Prepare the rollback copy while the previous host is still available.
    backup_root = Path(tempfile.mkdtemp(prefix='.genesis-rollback-',dir=args.release_dir.parent))
    backup = backup_root/'runtime'
    try:
        shutil.copytree(args.release_dir, backup)
        stop_owned(args, url, token, record)
    except (OSError, SetupError, ValueError, URLError, subprocess.SubprocessError):
        shutil.rmtree(backup_root)
        raise
    from types import SimpleNamespace
    next_args = SimpleNamespace(**vars(args))
    next_args.method = 'release'
    next_args.upgrade = False
    try:
        result = setup(next_args)
        result['previous_installation'] = str(backup)
        return result
    except (SetupError, OSError, ValueError, URLError, subprocess.SubprocessError) as error:
        # A newly launched candidate may own the port but have a broken MCP
        # endpoint. Ownership, rather than protocol health, identifies that host.
        if endpoint_listening(url):
            try:
                verify(url, token)
            except SetupError:
                require_idle = False
            else:
                require_idle = True
            stop_owned(args, url, token, json.loads(record_path.read_text()), require_idle=require_idle)
        if args.release_dir.exists():
            shutil.rmtree(args.release_dir)
        shutil.copytree(backup, args.release_dir)
        env = runtime_environment(args)
        launcher = Path(record['launcher'])
        if IS_WINDOWS:
            record['runtime_process'] = windows.start(launcher, url, args.config_dir, env)
        else:
            address=urlsplit(url)
            run([launcher,'start','--ip',address.hostname,'--port',str(address.port or 80),'--no-linger'],env)
        connector.write_private_json(record_path, record)
        deadline = time.monotonic()+30
        while True:
            try:
                verify(url, token)
                break
            except URLError as probe:
                if not refused(probe) or time.monotonic() >= deadline:
                    raise
                time.sleep(.25)
        raise SetupError('upgrade_failed', f'Upgrade failed; restored the previous installation. {error}') from error


def setup(args):
    version = json.loads((ROOT/'plugins/genesis/.codex-plugin/plugin.json').read_text())['version']
    os.environ.setdefault('GENESIS_VERSION', 'mcp-preview-'+version)
    os.environ.setdefault('GENESIS_DOWNLOAD_BASE', 'https://github.com/WLS2002/genesis/releases/download')
    os.environ.setdefault('GENESIS_DOWNLOAD_FALLBACK_BASE', 'https://github.com/WLS2002/genesis/releases')
    url = selected_url(args)
    agent = getattr(args, "agent", "codex")
    if agent == "codex" and not shutil.which("codex"):
        raise SetupError("codex_required", "Install Codex CLI with plugin support before connecting Genesis.")
    args.config_dir = args.config_dir.expanduser().resolve()
    args.release_dir = args.release_dir.expanduser().resolve()
    if args.config_dir.is_relative_to(args.release_dir):
        raise SetupError('config_directory', 'Keep the Genesis configuration directory outside the replaceable runtime directory.')
    token = connector.ensure_token(args.config_dir)
    started = False
    runtime_process = None
    try:
        status = verify(url, token)
    except URLError as error:
        if not refused(error):
            raise SetupError("connection_failed", "Cannot connect to the local Genesis endpoint: " + str(error.reason)) from error
        command = choose_launcher(args)
        service_env = dict(os.environ)
        if sys.platform.startswith("linux"):
            if args.config_dir.name != "genesis":
                raise SetupError("config_directory", "For automatic Linux startup, --config-dir must end in /genesis (XDG_CONFIG_HOME is its parent).")
            service_env["XDG_CONFIG_HOME"] = str(args.config_dir.parent)
        elif args.config_dir != connector.default_config_dir().resolve():
            raise SetupError("config_directory", "Automatic startup on this platform uses the default Genesis configuration directory.")
        # Keep setup non-interactive; do not change login/session service policy.
        service_env.setdefault("GENESIS_LINGER", "no")
        address = urlsplit(url)
        if IS_WINDOWS:
            runtime_process = windows.start(command, url, args.config_dir, service_env)
        else:
            run([command, "start", "--ip", "127.0.0.1" if address.hostname == "localhost" else address.hostname, "--port", str(address.port or 80), "--no-linger"], service_env)
        started = True
        connector.write_private_json(args.config_dir/'runtime.json', {
            'url':url, 'launcher':str(command), 'release_dir':str(args.release_dir),
            'runtime_process':runtime_process})
        deadline = time.monotonic() + 30
        while True:
            try:
                status = verify(url, token)
                break
            except URLError as error:
                if not refused(error) or time.monotonic() >= deadline:
                    raise SetupError("service_not_ready", "Genesis did not expose MCP at the requested address. Check its status/logs and the actual port; setup will not restart another instance.") from error
                time.sleep(.25)
    expected_release = os.environ.get('GENESIS_VERSION')
    if not expected_release or expected_release == 'latest':
        manifest = json.loads((ROOT/'plugins/genesis/.codex-plugin/plugin.json').read_text())
        expected_release = 'mcp-preview-' + manifest['version']
    build = status.get('build', {})
    expected_revision = getattr(args, 'expected_revision', None)
    if build.get('release') != expected_release or (expected_revision and build.get('revision') != expected_revision):
        if getattr(args, 'upgrade', False):
            return upgrade_owned(args, url, token)
        raise SetupError('upgrade_required',
            f"Expected {expected_release}" + (f" at {expected_revision}" if expected_revision else '') +
            f", but the service at {url} reports {build or 'an unidentified build'}. "
            "Inspect active tasks, stop the previous Genesis host, then rerun with --method release. User configuration is preserved.")
    if agent == 'codex':
        status = connector.connect(url, args.config_dir, args.codex_home, output=sys.stderr)
    mcp_config = args.config_dir / 'mcp-client.json'
    connector.write_private_json(mcp_config, {'mcpServers': {'genesis': {
        'type': 'http', 'url': url, 'headers': {'Authorization': 'Bearer '+token}}}})
    origin = url.rsplit("/mcp", 1)[0]
    ready = bool(status.get("model_ready"))
    return {
        "status": "ready" if ready else "needs_model_configuration",
        "service_started": started, "plugin_installed": agent == "codex",
        "build": build, "mcp_config_file": str(mcp_config),
        "skill_path": str(ROOT / "plugins/genesis/skills/genesis"),
        "runtime_process": runtime_process,
        "configuration_ready": ready, "provider_connection_tested": False,
        "mcp_url": url, "dashboard_url": origin, "settings_url": origin + "/settings",
        "config_files": status.get("config_files", {}),
        "source_root": str(ROOT), "warnings": status.get("warnings", []),
        "next_steps": (["Load the Genesis Skill and private MCP connection in your coding agent, then run genesis_check and genesis_list_models."] if ready else
                       ["Follow the installed Skill's references/configuration.md: ask for the missing provider/model and authentication choice, and preserve existing configuration.",
                        "Use config_files from this result. Prepare non-secret model configuration; let the user fill credentials locally or complete vendor CLI login on the Genesis host.",
                        "In a session with the tools loaded, call genesis_reload_config to apply file edits, then genesis_check and genesis_list_models. No Genesis dashboard interaction is required."])
    }


def main(argv=None, default_agent="codex"):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", help="Local MCP URL; otherwise use the lifecycle launcher saved URL, then http://127.0.0.1:9999/mcp")
    parser.add_argument("--config-dir", type=Path, default=connector.default_config_dir())
    parser.add_argument("--codex-home", type=Path)
    parser.add_argument("--upgrade", action="store_true", help="Upgrade an idle instance owned by this installer; keep a rollback copy")
    parser.add_argument("--agent", choices=["none", "codex"], default=default_agent)
    parser.add_argument("--expected-revision", default=os.environ.get("GENESIS_EXPECTED_REVISION"))
    parser.add_argument("--server-command", help="Path to bin/genesis, or the native Windows genesis-desktop.exe host")
    parser.add_argument("--method", choices=["auto", "source", "release"], default="auto")
    parser.add_argument("--release-dir", type=Path, default=windows.default_install_dir() if IS_WINDOWS else Path.home()/".local/share/genesis/server")
    parser.add_argument("--json", action="store_true", help="Print structured status; progress/commands go to stderr")
    args = parser.parse_args(argv)
    try:
        result = setup(args)
        code = 0 if result["configuration_ready"] else 2
    except (SetupError, OSError, ValueError, URLError, subprocess.SubprocessError) as error:
        result = {"status": "error", "code": getattr(error, "code", "setup_failed"), "message": str(error)}
        code = 1
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print("Genesis setup: " + result["status"])
        if "message" in result:
            print(result["message"])
        else:
            print("Dashboard: " + result["dashboard_url"])
            for step in result["next_steps"]:
                print("- " + step)
    return code


if __name__ == "__main__":
    sys.exit(main())
