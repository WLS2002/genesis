# Configure Genesis from the calling agent

Complete model setup through local files and MCP. The user can use Genesis entirely from the calling agent; the Genesis dashboard is an optional viewer.

## Locate and choose

Call `genesis_check` and use its `config_files.config` and `config_files.credentials`. These are absolute paths on the **Genesis host**, using that service's actual platform/configuration directory. The Codex setup result includes the same fields. Edit on that host; a calling agent's separate container or home directory may not be the service's filesystem.

Reuse a working profile. When a model is missing, ask for the provider, model ID and authentication method; ask for a custom base URL only when needed. A subscription for the calling agent does not automatically select or authenticate a Genesis model. Obtain the user's choice before changing an existing default. The first profile is the default.

## Prepare non-secret configuration

Merge the selected profile into `config_files.config`, preserving other settings and profiles. Use unique profile IDs. For an existing flat `[llm] model` configuration, preserve its effective settings when migrating to profiles; avoid duplicate TOML tables. The examples below are shapes: replace `SELECTED_MODEL_ID` and any endpoint placeholder with the user's actual choice before saving.

API-key profile:

```toml
[[llm.models]]
id = "default"
model = "openai:SELECTED_MODEL_ID"
```

Use the chosen provider prefix, such as `openai` or `anthropic`. For an OpenAI-compatible custom endpoint, the actual provider is `openai`:

```toml
[[llm.models]]
id = "custom"
model = { provider = "openai", id = "SELECTED_MODEL_ID", base_url = "https://YOUR_ENDPOINT/v1" }
```

ChatGPT/Codex subscription:

```toml
[[llm.models]]
id = "codex"
model = "openai_codex:SELECTED_MODEL_ID"
```

Claude subscription:

```toml
[[llm.models]]
id = "claude"
model = "anthropic:SELECTED_MODEL_ID"
auth_mode = "oauth"
```

## Complete authentication locally

**API key:** prepare a private `config_files.credentials` file if needed (directory mode `0700`, file mode `0600` on POSIX), preserving existing entries. Tell the user its exact absolute path and the required top-level TOML key, for example `OPENAI_API_KEY = "..."` or `ANTHROPIC_API_KEY = "..."`. The user fills the real value in their local editor and reports completion. Keep secrets out of chat, tool arguments, logs and project files; inspect presence/parse success without printing values. Use the provider's credential key, not the profile ID. An empty placeholder is not a credential.

**Subscription:** reuse an available vendor CLI login on the Genesis host under the account running Genesis. If needed, ask the user to complete `codex login` for `openai_codex`, or run `claude` and log in for an Anthropic OAuth profile. The vendor's login may open its own authentication page; no Genesis GUI interaction is required. Genesis imports the login into its managed OAuth file when resolving the profile. Preserve that file and let the existing importer/refresh mechanism manage it. For custom OAuth paths, environment-token alternatives or login problems, read the source checkout's `docs/llm-oauth.md` when available.

## Load and verify

After file edits or login, call `genesis_reload_config` with `{}`. This strictly reads configuration/credentials and applies scheduler settings using the existing Genesis reload mechanism. Syntax/schema failure returns `configuration_not_applied` and leaves the running scheduler configuration unchanged. Fix the named file/keys and retry. Running agents retain their existing settings; node distribution changes require a service restart.

Then call `genesis_check` and `genesis_list_models`. `configuration_reloaded=true` means loading succeeded; `model_ready` and `warnings` separately report configuration completeness. The checks make no provider request (`provider_connection_tested=false`), so account access and network connectivity remain untested until intended development uses the provider. Do not submit a paid test task solely to complete installation.

Report what is ready, the selected profile, and any exact remaining file/login action. If newly installed tools are not loaded, open/reload the host session before this step. The calling agent can submit and track the user's development task once configuration checks pass; browser task links remain optional.
