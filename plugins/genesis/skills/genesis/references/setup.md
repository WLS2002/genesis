# Set up or repair a Genesis connection

This reference travels with the portable Genesis Skill. Prepare the common Genesis service, connect its MCP endpoint using the current host's own mechanism, and load the shared workflow. Preserve existing configuration and other installed tools.

## Locate the source

If this installation includes `installation.json` beside this file, read its `source_root` to locate the original checkout and its root `INSTALL.md`. Otherwise use the repository/ref provided by the user. The Skill directory need not contain repository scripts. If the checkout moved, locate or clone the requested version; preserve local changes and use a checkout or binary containing MCP support.

## Prepare the common service

Inspect the environment and existing Genesis address before installing another instance. A compatible existing service can be reused. For binary installation use the checkout's `scripts/install.sh`; for a source build follow its README/INSTALL toolchain instructions and build `genesis_server`. Start through the existing `genesis` lifecycle launcher. Default headless address: `http://127.0.0.1:9999`.

The selected release must provide the nine Genesis tools, including `genesis_reload_config`. Resolve an incompatible running instance explicitly; do not silently replace it or create a second service against the same data. Source-development/desktop instances may use another address; use their displayed URL.

## Register this host

For **Codex**, read [the Codex adapter](adapters/codex.md) for automatic setup, private plugin registration, options and return codes.

For **another compatible host**, read the source checkout's `docs/agent-mcp.md` when available. Register Streamable HTTP at the instance's `/mcp` endpoint. Create or reuse a private `mcp-token` in the configuration directory the server actually uses (at least 32 random URL-safe characters; POSIX mode `0600`), then configure persistent `Authorization: Bearer <token>` using the host's supported secret/header mechanism. Do not put credentials into chat or repository files. MCP registration syntax and environment expansion are host-specific; do not copy a Codex manifest into an unrelated host.

Load this Skill and its references through the host's supported Skill mechanism, or load the Skill body and overview as its collaboration instructions while preserving/adapting reference paths. The host needs HTTP MCP and persistent bearer authentication support; other hosts have not yet been individually validated.

## Verify and continue

Reload or open a new host session as needed. Discover `genesis_check`, `genesis_reload_config`, `genesis_start_task`, `genesis_get_task`, `genesis_list_tasks`, `genesis_cancel_task`, `genesis_list_models`, `genesis_get_result` and `genesis_send_message`. Call `genesis_check`; for missing model configuration, authentication or file edits, follow [configuration](configuration.md). Ask only for the missing choices or local credential/login actions, then load and recheck through MCP.

Service availability, tool access and model configuration are separate checks. Readiness makes no paid provider request and does not prove entitlement/connectivity. Report the actual URL, connection state and any remaining file/login action. Submit development only for the user's intended work, then follow the shared workflow. The Genesis dashboard is an optional viewer throughout.
