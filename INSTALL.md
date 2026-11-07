# Install Genesis for your Coding Agent

Give your agent the repository URL and ask:

> Install Genesis from this repository and connect it to my coding agent. Follow INSTALL.md, preserve my existing configuration, and tell me what is ready or still needs my input.

This guide is for the agent carrying out that request. Complete the local installation and checks yourself. Ask for missing repository/ref information, the user's model/provider choice or interactive credentials when needed. Use the current host's integration mechanism for the final connection step.

## MCP preview installation

The MCP preview lives on [`WLS2002/genesis`, branch `feat/mcp-codex`](https://github.com/WLS2002/genesis/tree/feat/mcp-codex). Clone that branch when given its GitHub link; a plain clone of the repository's default branch does not select the preview.

For **Linux x64**, use the matching [MCP preview release](https://github.com/WLS2002/genesis/releases/tag/mcp-preview-0.4.0). It bundles Erlang/Elixir and needs no source toolchain. Prepare Python 3.9+, Git, `curl` or `wget`, and `tar` with xz support. Run from this checkout:

```sh
export GENESIS_VERSION=mcp-preview-0.4.0
export GENESIS_DOWNLOAD_BASE=https://github.com/WLS2002/genesis/releases/download
export GENESIS_DOWNLOAD_FALLBACK_BASE=https://github.com/WLS2002/genesis/releases
python3 scripts/setup-codex.py --method release --json
```

For another compatible coding agent, use the same download settings with `sh scripts/install.sh`, start Genesis, then follow the [shared connection contract](docs/agent-mcp.md#connection-contract). The automatic setup command above is the Codex adapter.

This preview publishes a Linux x64 server, built on Ubuntu 22.04. Other platforms can build this branch from source with the toolchain below; upstream desktop downloads and older upstream server releases do not contain this MCP implementation. Preserve a running installation and its data; resolve a conflicting service explicitly before upgrading or starting a separate instance.

## 1. Locate the requested version and environment

Reuse or clone the repository/ref supplied by the user. Inspect local changes before switching versions. Use the MCP preview branch and matching release above, or build the selected MCP-capable checkout. Public default branches and older releases may not contain this implementation.

Inspect OS, architecture, package manager and available tools. Source builds require Git, Elixir 1.20.4 and Erlang/OTP 29 plus the checkout's native build dependencies; reuse the established toolchain. The existing release installer supports Linux x64/arm64 and macOS arm64. Host integration additionally requires a local HTTP MCP client able to send persistent authorization headers. The validated automatic adapter is currently Linux with Codex CLI 0.167.0.

## 2. Prepare and start Genesis

Identify any running Genesis instance and use its actual address/configuration. Lifecycle-managed installs expose `genesis url` and `genesis status`; a source development server commonly uses port4100, and a desktop instance displays its own URL. Resolve the existing instance before starting another against the same data. Preserve model/credential files and local work.

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
mix deps.get
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release genesis_server
_build/prod/rel/genesis_server/bin/genesis start
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
