# Codex adapter

This is the verified Codex-specific adapter for the shared [Coding Agent integration guide](agent-mcp.md). For service installation, host selection and model configuration, start at [INSTALL.md](../INSTALL.md).

After connecting, ask:

> Use Genesis to implement this feature in the current project. Follow its progress and inspect the result.

Genesis runs its own configured models and keeps tasks in its existing task history. Codex submits the objective, checks progress and reads the saved result. Closing Codex does not cancel the task. Git commits, result branches and review follow Genesis's existing behavior.

## Install

Give Codex the repository URL and ask it to **install Genesis for Codex following [INSTALL.md](../INSTALL.md)**. That guide starts with a cold environment, covers prerequisite detection and model login, and tells the agent to perform the local work. Use the user-selected repository and ref. For the MCP preview, follow its [pinned native binary instructions](../INSTALL.md#mcp-preview-installation); older upstream releases lack these tools.

The first validated setup is **Linux with Codex CLI 0.167.0**. The connector requires `codex plugin` support and Python 3.9+. Source builds use **Elixir 1.20.4 and Erlang/OTP 29**, matching this repository's build environment.

From the selected checkout, run:

```sh
python3 scripts/setup-codex.py --json
```

Setup reuses a reachable compatible service; otherwise it selects an installed lifecycle launcher or local built server. The default `--method auto` builds from source when the Elixir toolchain is available and uses the existing release downloader otherwise. The preview's binary instructions explicitly pin its download source and `--method release`. To build this branch from source:

```sh
python3 scripts/setup-codex.py --method source --json
```

Setup starts Genesis in the background, verifies the MCP tools, and installs the private plugin through `codex plugin`. It preserves existing model and credential configuration. A running incompatible service produces an actionable error; setup does not silently replace or restart it. Resolve that service before starting another instance.

Read service readiness, plugin installation and model readiness separately. Exit **0** (`ready` / `configuration_ready`) means configuration checks pass; exit **2** (`needs_model_configuration`) means a model/credential choice remains, even though Genesis can be running and the plugin installed; exit **1** means setup failed. These checks inspect configuration without making a paid provider request. They do not establish provider connectivity or subscription entitlement.

For missing model setup, follow the portable [file and CLI configuration guide](../plugins/genesis/skills/genesis/references/configuration.md). Setup returns `config_files` from the service: prepare the selected non-secret profile, let the user fill the private credential file or complete vendor login, then call `genesis_reload_config` and recheck. The Genesis dashboard link is optional.

Useful setup options:

```sh
python3 scripts/setup-codex.py --url http://127.0.0.1:10000/mcp
python3 scripts/setup-codex.py --server-command /absolute/path/bin/genesis
```

Use `--config-dir` for the selected instance's configuration directory, `--codex-home` for a separate Codex profile, `--method auto|source|release` to select provisioning, and `--release-dir` for a release download destination. Check `--help` for the current interface. `python3 scripts/install-codex.py` is the connector-only option when a compatible service is already running; it does not build or launch the service.

Open a new Codex session if it has not loaded the installed plugin, then ask it to use the Genesis skill and check readiness. Codex may request approval for task operations under its own policy. The nine tools are `genesis_check`, `genesis_start_task`, `genesis_get_task`, `genesis_list_tasks`, `genesis_cancel_task`, `genesis_list_models`, `genesis_get_result`, `genesis_send_message` and `genesis_reload_config`. The installed skill includes a [caller/Genesis overview](../plugins/genesis/skills/genesis/references/overview.md) and a [self-contained setup reference](../plugins/genesis/skills/genesis/references/setup.md).

## What gets installed

On Linux, the connector writes under `${XDG_CONFIG_HOME:-~/.config}/genesis`:

- `mcp-token`: a private bearer token, reused on reinstall.
- `codex/`: a private local marketplace with the Genesis plugin, skill and persistent HTTP authorization header.

Codex installs `genesis@genesis-mcp-local` into its own plugin cache. No shell export is required for the next session. Keep the token and generated plugin/cache files private; do not commit or share the generated marketplace. The repository's `plugins/genesis` directory contains only the distributable, credential-free template.

MCP is disabled until a valid token file exists. The endpoint accepts loopback connections with a matching host, token and valid Origin. It does not trust forwarded client addresses and is not a remotely accessible management API. The dashboard and its existing routes are unchanged.

To uninstall the connector, run `codex plugin remove genesis@genesis-mcp-local` and `codex plugin marketplace remove genesis-mcp-local`. Removing `mcp-token` disables MCP access; it does not stop Genesis or delete tasks.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Connection refused | Start Genesis and check the selected port with its existing status/log commands. |
| HTTP 404 | The running release lacks MCP support; update/build and restart it. |
| HTTP 401/503 | Ensure the connector and running server use the same Genesis config directory; rerun the connector. |
| Plugin installed but tools absent | Open a new Codex session and check the MCP connection status. |
| Model not ready | Complete file/CLI model configuration and call `genesis_reload_config`. Installing the Codex plugin does not configure a model. |
| Task failed | Read `genesis_get_task` and Genesis logs; report the saved failure rather than resubmitting automatically. |

## Shared workflow

Use the same [task and result workflow](agent-mcp.md#tasks-and-results), [long-task guidance](agent-mcp.md#following-long-tasks) and [caller/engine handoff](../plugins/genesis/skills/genesis/references/overview.md) as other hosts. Codex-specific approval and plugin loading follow its host policy.

## Native platforms and WSL

The [installation entry](../INSTALL.md#mcp-preview-installation) contains the common pinned release and platform commands. Linux/macOS use the existing service CLI. Windows x64 uses the existing desktop host's `--headless` mode in a portable package; `runtime_process` in setup JSON reports the PID and log of a newly started host. To stop that native host, cancel active tasks first and stop its reported process through PowerShell; its lifetime connection shuts down the backend. It is a background login process, not an automatically registered Windows service.

When using a custom port on native Windows, retain the returned MCP URL and pass it with `--url` on later setup/repair runs. For a source-built native desktop host, pass `--server-command <path-to-genesis-desktop.exe>`. Model/token files use the actual `%APPDATA%` directory reported by the service, and private files inherit the user's NTFS directory permissions.

Inside WSL, use the Linux workflow for both Codex and Genesis. A native Windows Codex configuration, Windows model login or `C:\...` project path is not a Linux-side configuration. Keep projects and vendor login in the selected environment; the shared MCP endpoint remains local-only.
