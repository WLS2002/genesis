Genesis MCP preview for Linux, macOS, native Windows and WSL.

Start with [INSTALL.md](https://github.com/WLS2002/genesis/blob/mcp-preview-0.5.0/INSTALL.md). It selects the platform, pins this preview's download source, connects MCP and loads the shared Skill. Model setup and development can stay in the calling agent; the Genesis GUI is optional.

| Package | Environment |
| --- | --- |
| Linux x64 / arm64 | Headless server; Ubuntu 22.04+ / glibc 2.35+ |
| macOS Intel / Apple Silicon | Native headless server; macOS 15+ |
| Windows x64 | Portable existing desktop host with `--headless`; no GUI installer or window |
| WSL 2 | Linux package; run the caller, service, project and vendor login inside the same distribution |

The packages include Erlang/Elixir and the established bundled development tools. Codex CLI 0.167.0 has the automatic adapter. Other compatible HTTP MCP hosts use the shared service and Skill with their own registration mechanism.

Nine tools cover readiness/configuration reload, model discovery, task submission, progress/history, added instructions, cancellation and finished results. Choose the Genesis model and complete authentication locally through credential files or vendor CLI login, then load and check through MCP. Installation readiness makes no paid provider request and does not establish account entitlement.

Each native package passes installation, live MCP/configuration checks and actual Codex CLI plugin registration before publication. WSL reuses the Linux package and installation workflow. See the per-platform build-info JSON and SHA256 files for exact provenance.

This is a trial prerelease, separate from upstream stable releases. Internal application version remains 0.14.0; the portable Skill/plugin is 0.5.0.
