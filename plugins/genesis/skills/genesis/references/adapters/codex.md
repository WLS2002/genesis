# Set up or repair Genesis for Codex

This reference travels with the installed plugin. Work through local setup yourself; ask the user for a missing repository/ref, model/provider choice, credentials or an interactive vendor login when needed. Preserve the current Genesis configuration and other Codex plugins.

## Locate setup

Read `../installation.json` in the parent reference directory. The installer records `source_root` there; if that checkout still exists, read its root `INSTALL.md` and run its `scripts/setup-codex.py --help`. This locates the source without assuming the installed plugin cache contains repository scripts. If the recorded checkout has moved or the metadata is absent, use the repository URL/ref supplied by the user to locate or clone the desired version. Keep the selected checkout's local changes. For an unreleased feature present only in local changes, use that checkout rather than an unrelated clone or public release.

Detect OS/architecture, package manager and available tools. The first validated connector environment is Linux with Codex CLI 0.167.0; it requires Codex plugin support and Python 3.9+. Install missing local prerequisites with established environment tooling where authorized. For the MCP preview's Linux x64 binary, follow the source checkout's `INSTALL.md` preview section, including its pinned download environment and `--method release`. Source builds require Git, **Elixir 1.20.4 and Erlang/OTP 29**, and the selected checkout's native build dependencies. Other binary downloads must also contain MCP support; the installer supporting a platform does not mean an MCP preview asset exists for it.

## Provision and connect

Run from the source checkout:

```sh
python3 scripts/setup-codex.py --json
```

`--method auto` reuses a reachable compatible service, then looks for an installed Genesis lifecycle launcher or locally built server. When no server is available, it builds from source if the toolchain exists and otherwise invokes the existing release downloader. Use `--method source` to build the selected feature checkout explicitly, or `--method release` only for a known MCP-capable published version.

Setup starts Genesis in the background, verifies its nine MCP tools and installs the private Codex plugin. Preserve a running service and its model/credential configuration. An incompatible reachable instance must produce an actionable failure. Resolve its version/configuration before any replacement or restart; avoid a second instance pointing at the same data.

Options:

| Option | Purpose |
| --- | --- |
| `--url` | Local MCP endpoint; otherwise use the lifecycle launcher’s saved URL, then `http://127.0.0.1:9999/mcp`. |
| `--config-dir` | Configuration directory used by the selected Genesis instance. |
| `--codex-home` | Separate Codex profile to receive the plugin. |
| `--server-command` | Explicit path to the Genesis lifecycle launcher (`bin/genesis`). |
| `--method auto\|source\|release` | Provisioning choice. |
| `--release-dir` | Downloaded release destination. |
| `--json` | Structured readiness and next steps. |

For an already running compatible instance, `python3 scripts/install-codex.py` installs only the connector. Run that command from the source checkout too; it does not launch or build Genesis. Rerunning setup preserves existing private token/configuration. Keep generated token, marketplace and authorization headers out of repository files and messages.

## Finish model configuration

Read service/plugin state separately from model readiness. Exit **0** (`ready` / `configuration_ready`) means configuration checks pass. Exit **2**, `needs_model_configuration`, means a model/credential choice remains; the service may already be running and the plugin installed. Exit **1** means setup failed. Read the accompanying next steps before retrying.

Follow [file and CLI configuration](../configuration.md) for the shared model/authentication workflow. The setup result returns `config_files` from the running service. Prepare non-secret configuration at that location; the user fills private credentials locally or completes vendor CLI login. The Genesis dashboard is optional.

Call `genesis_reload_config` after file edits or login, then `genesis_check` and `genesis_list_models`. These checks inspect configured readiness and make no paid provider request; they do not prove provider connectivity or account entitlement. Do not start a development task solely to test installation. Report the service URL, plugin state, model state and any precise remaining action. Claim development readiness only after all configuration checks pass.

Open a new Codex session when the current session has not loaded newly installed tools. A new session should expose `genesis_check`, `genesis_start_task`, `genesis_get_task`, `genesis_list_tasks`, `genesis_cancel_task`, `genesis_list_models`, `genesis_get_result`, `genesis_send_message` and `genesis_reload_config`.

## Diagnose an existing connection

| Observation | Next action |
| --- | --- |
| Connection refused | Inspect the selected launcher's `status`/`logs`; run setup against the intended port. |
| HTTP 404 or missing tools | Identify the running release; build/install a version with MCP support before coordinating a restart. |
| HTTP 401/503 | Check that setup and service use the same config directory/token; rerun the connector after correcting the directory. |
| Tools absent after installation | Open a new session and inspect Codex's MCP connection state. |
| Model configuration incomplete | Follow the configuration reference, load file edits and repeat readiness checks. |

To remove this connector, use `codex plugin remove genesis@genesis-mcp-local` and `codex plugin marketplace remove genesis-mcp-local`. Removing the Genesis config directory's `mcp-token` disables MCP access. These actions do not stop Genesis or delete tasks.

For an already running source-development or desktop instance, inspect its displayed URL and pass it explicitly with `--url` (the usual development port is 4100). Automatic discovery reads lifecycle-managed server URLs; it does not enumerate arbitrary running processes or desktop ports. Resolve an existing instance using the same data before starting another.
