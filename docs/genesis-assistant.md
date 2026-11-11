# Genesis Assistant

The `/help` page is a conversational operator for Genesis tasks. It uses the same nine task-control tools as external MCP clients through an in-process adapter. The existing project homepage and global navigation remain the entry points.

## Shared task control

`EvoGit.TaskControl.Tools` owns tool names, descriptions, input schemas and dispatch to `EvoGit.TaskControl`. `EvoDash.MCP.Tools` adds the HTTP tool-result envelope, annotations and browser links. `EvoGit.Agent.Tools.GenesisTools` renders the same business results as model-facing text. Neither adapter owns another task lifecycle.

The assistant advertises `genesis_check`, `genesis_reload_config`, `genesis_start_task`, `genesis_get_task`, `genesis_list_tasks`, `genesis_cancel_task`, `genesis_list_models`, `genesis_get_result` and `genesis_send_message`, plus `web_fetch` and configuration-gated `web_search`. See [MCP task semantics](agent-mcp.md) for task status, observations, queued messages and cancellation.

A task objective must include its own context and acceptance criteria. The conversation is not inherited by development agents. When a project path was not supplied, the assistant asks for an absolute directory on the selected Genesis host. A new project starts in an existing empty directory. Provider/model edits are made through Settings or by the user in the configuration files reported by `genesis_check`; the assistant can then reload and validate configuration.

## Source-independent runtime

The existing `:reflect` task kind still starts the assistant. `Runtime.SelfReflective.build_spec/2` creates a minimal `[system]` context node and forces repo-less execution. The scheduler supplies a runtime working directory; the runner does not create a code worktree or load source CONTEXT/project skills for repo-less agents. Model/account selection remains part of the existing task admission path.

Chatting does not require downloading the Genesis source. The former `/help` source gate and its asynchronous probe/download callbacks are removed. Optional source-reference management remains available in System settings, and the legacy evaluator implementation, dispatch, serial execution and approval paths remain for compatibility. Those tools are not advertised by the new assistant.

## Existing page behavior

The page keeps the current composer and model picker, per-node model snapshots, in-memory chat history, streaming and task-status handling. Node changes cannot submit against a stale model snapshot. Legacy pending approvals can still be recovered and answered. Task polling has outer dispatch headroom for its bounded 20-second wait. Cancellation and queued messages report the existing service acknowledgement, not process cleanup or delivery confirmation.

A reply without tool calls ends the current assistant run and becomes its answer. Background development tasks have independent IDs and lifecycles; their progress reports and saved results remain separate from independent verification of the changes.
