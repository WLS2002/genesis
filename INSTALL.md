# Install Genesis for your Coding Agent

Give your agent the repository URL and ask:

> Install Genesis from this repository and connect it to my coding agent. Follow INSTALL.md, preserve my existing configuration, and tell me what is ready or still needs my input.

This guide is for the agent carrying out that request. Complete the local installation and checks yourself. Ask for missing repository/ref information, the user's model/provider choice or interactive credentials when needed. Use the current host's integration mechanism for the final connection step.

## MCP preview installation

The MCP preview lives on [`WLS2002/genesis`, branch `feat/mcp-codex`](https://github.com/WLS2002/genesis/tree/feat/mcp-codex). Clone that branch when given its GitHub link; a plain clone of the repository's default branch does not select the preview.

Use the matching [MCP preview release](https://github.com/WLS2002/genesis/releases/tag/mcp-preview-0.6.1). It includes the runtime, so an Erlang/Elixir source toolchain is unnecessary.

| Environment | Package / preparation |
| --- | --- |
| Linux x64 / arm64 | Native server archive; Linux builds target Ubuntu 22.04 or newer (glibc 2.35+). |
| macOS Apple Silicon / Intel | Native server archive for the actual architecture; macOS 15+. |
| Windows x64 | Portable host ZIP, running the existing `--headless` mode; no desktop window or GUI installer. |
| WSL 2 | Use the Linux package inside the distribution; run the coding agent, Genesis and project there. |

Prepare Python 3.9+, Git and the current coding agent. Linux/macOS also need `curl` or `wget`, and `tar` with xz support. Windows uses Python's standard ZIP/download support. Run from this checkout.

**Linux, macOS, or a coding agent running inside WSL:**

```sh
export GENESIS_VERSION=mcp-preview-0.6.1
export GENESIS_DOWNLOAD_BASE=https://github.com/WLS2002/genesis/releases/download
export GENESIS_DOWNLOAD_FALLBACK_BASE=https://github.com/WLS2002/genesis/releases
python3 scripts/setup-codex.py --method release --json
```

**Native Windows, PowerShell:**

```powershell
$env:GENESIS_VERSION = "mcp-preview-0.6.1"
$env:GENESIS_DOWNLOAD_BASE = "https://github.com/WLS2002/genesis/releases/download"
$env:GENESIS_DOWNLOAD_FALLBACK_BASE = "https://github.com/WLS2002/genesis/releases"
python scripts/setup-codex.py --method release --json
```

The shared setup entry chooses the current platform. Native Windows installs under `%LOCALAPPDATA%\Genesis\server`, reuses Genesis's existing headless desktop host and reports its PID/log path as `runtime_process`. Model/token files live in the backend's `%APPDATA%\genesis`. This starts a background process for the current login, without registering an administrator service. Linux/macOS retain the original `genesis` lifecycle CLI.

Register the MCP URL returned by setup, including its port. Port 9999 is only the headless default; a separately launched desktop window may use a different port. Use the shared setup entry for Coding Agent integration instead of a hand-written start script. On Windows, custom Start-Process commands must use different files for RedirectStandardOutput and RedirectStandardError.

For another compatible coding agent, run `python scripts/setup-genesis.py --method release --json` with the same download settings. It prepares the same service without installing or invoking Codex. Register the private MCP connection and load the returned Skill using the [shared connection contract](docs/agent-mcp.md#connection-contract).

Keep the calling agent, Genesis, repository and credentials in the same environment. For a native Windows agent use the native Windows package; for WSL run both agent and service inside WSL with Linux project paths. WSL does not translate a native host's MCP registration or vendor login automatically. If WSL is absent, use native Windows or ask the user to complete OS provisioning that requires elevation/restart.

Preserve a running installation and its data; resolve a conflicting service explicitly before upgrading or starting a separate instance. Upstream default branches/older packages do not contain this MCP preview. Source building remains available below for POSIX systems; native Windows source builds use the existing desktop host build and `--server-command`.

## 1. Locate the requested version and environment

Reuse or clone the repository/ref supplied by the user. Inspect local changes before switching versions. Use the MCP preview branch and matching release above, or build the selected MCP-capable checkout. Public default branches and older releases may not contain this implementation.

Inspect OS, architecture, package manager and available tools. Source builds require Git, Elixir 1.20.4 and Erlang/OTP 29 plus the checkout's native build dependencies; reuse the established toolchain. The preview provides Linux x64/arm64, macOS x64/arm64 and native Windows x64 packages. Host integration additionally requires a local HTTP MCP client able to send persistent authorization headers. The automatic adapter targets Codex CLI 0.167.0 with plugin support; use the current native platform package.

## 2. Prepare and start Genesis

Identify any running Genesis instance and use its actual address/configuration. Lifecycle-managed installs expose `genesis url` and `genesis status`; a source development server commonly uses port4100, and a desktop instance displays its own URL. Resolve the existing instance before starting another against the same data. Preserve model/credential files and local work.

For any supported host, including DeepSeek Harness, prepare the service with:

```sh
python scripts/setup-genesis.py --method release --json
```

The result contains `build`, `mcp_url`, a private `mcp_config_file` and `skill_path`. Register that connection with the host and load the Skill. The private JSON uses common HTTP MCP `headers`; adapt field names to the host's documented syntax without printing the token. Codex is optional.

Compare `build.release` with the selected preview; use `--expected-revision <source-sha>` when testing an exact checkout. A reachable endpoint alone does not prove the intended runtime is installed. `--upgrade` replaces only an idle installation with a matching `runtime.json` ownership record, preserves user configuration and keeps a rollback copy. For an older installation without that record, inspect its tasks and stop its headless host before rerunning with `--method release`.

Choose a host adapter where available:

- **Codex:** follow the [Codex adapter](docs/codex-mcp.md). Its `python3 scripts/setup-codex.py --json` command orchestrates preparation, startup and private plugin registration. The script and its `--codex-home` options are specifically for Codex.
- **Other hosts:** prepare the same Genesis service below, then register it using the [shared MCP connection contract](docs/agent-mcp.md#connection-contract) and that host's documented configuration mechanism.

To install a published MCP-capable binary, use the existing installer from this checkout:

```sh
sh scripts/install.sh
genesis start
genesis status
```

If `genesis` is not on PATH, use the installed `bin/genesis` path printed by the installer. To build the current feature checkout:

```sh
python3 scripts/setup-genesis.py --method source --json
```

The default headless dashboard is `http://127.0.0.1:9999`. Use the actual configured address if different. A running release without the required MCP tools needs an explicit upgrade/restart decision; do not silently replace it.

## 3. Connect tools and load the shared workflow

Follow [MCP connection and instruction loading](docs/agent-mcp.md). The endpoint is `/mcp`; it uses a private token from the running instance's configuration directory. Register the connection using the selected host's supported authentication/secret storage. Install the portable Genesis Skill with its references, or load the same collaboration instructions through the host's context mechanism.

The service, tools and workflow are shared. Only registration, persistent credentials and instruction loading belong in a host adapter. Existing Codex scripts remain the Codex implementation of those steps; other agents do not need to install Codex to use Genesis.

## 4. Finish model configuration and verify

Reuse valid model profiles. For missing models or authentication, follow [configuration from the calling agent](plugins/genesis/skills/genesis/references/configuration.md). `genesis_check.config_files` reports the actual service-side configuration and credentials paths. Ask for the missing provider/model/auth choice, prepare non-secret configuration, and let the user fill credentials locally or complete the chosen vendor CLI login. Apply edits with `genesis_reload_config`, then recheck. This workflow requires no Genesis GUI interaction.

Verify three things separately: the service responds, a fresh host session discovers all nine tools and calls `genesis_check`, and Genesis model configuration is ready. Configuration checks do not make a paid provider request and do not establish connectivity or entitlement. A user-authorized development task is the next operational check.

If model choice or login remains, report installed components, the exact configuration file path or vendor login command and the precise remaining user action. When configuration is ready, report the connection URL and explain how to ask the current agent to use Genesis. Report task progress in the calling agent; offer task links as optional views. Localhost links open on the Genesis machine.

For subsequent development use the [shared workflow](docs/agent-mcp.md#tasks-and-results) and [caller/Genesis overview](plugins/genesis/skills/genesis/references/overview.md). Codex-specific setup return codes, options and plugin maintenance live in the [Codex adapter](docs/codex-mcp.md).

For a controlled Windows/DeepSeek Harness retest, follow [the retest checklist](docs/windows-mcp-retest.md).
