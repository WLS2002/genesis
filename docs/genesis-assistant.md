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

The page keeps per-node model snapshots, in-memory chat history, streaming and task-status handling. Node changes cannot submit against a stale model snapshot. Legacy pending approvals can still be recovered and answered. Task polling has outer dispatch headroom for its bounded 20-second wait. Cancellation and queued messages report the existing service acknowledgement, not process cleanup or delivery confirmation.

A reply without tool calls ends the current assistant run and becomes its answer. Background development tasks have independent IDs and lifecycles; their progress reports and saved results remain separate from independent verification of the changes.

## Assistant workspace

## Choose a project

Use the project control below the Assistant title. Choose a recent project or enter the full path of an existing directory on the selected machine. Project selection happens in the Assistant page and preserves your draft.

You can prepare a message before selecting a project. Sending requires a project and an available model. Changing the project is disabled while the current reply runs so that the visible context continues to describe that reply.

## Write and follow a conversation

Type a request in the composer:

- **Enter** sends; **Shift+Enter** adds a new line. Confirming text with an input method does not send it.
- The starter buttons prepare an editable draft; they do not start a task immediately.
- While the Assistant works, you can write the next message. Send it after the current reply finishes, or use **Stop** to interrupt the current reply first. Typing a draft does not steer or queue a message to a running task.
- Task results appear in the conversation. The Assistant should distinguish a task being accepted from the work being completed, and report returned status and outcomes.

Choose a model from the compact control inside the composer. Its expanded panel contains the existing provider-profile, model, and supported reasoning-effort selections. This choice applies to Assistant turns; it does not edit global model defaults. The picker is scoped to the selected node, and unavailable or stale choices must be resolved before sending.

## Return to an earlier conversation

Use the clock button beside **New chat** to open conversation history for the selected node. Select a conversation to restore its transcript, draft, project, and model choice. New chat retains the current project and same-node model preference. Stop or finish the current reply before creating or switching conversations.

History uses the existing in-memory store and retains the ten newest conversations. It survives page navigation and remounts, but does not survive a server restart. Unsent drafts are also cached in the browser session, separately for each node and conversation; this does not add cross-restart conversation storage. Existing pending approvals are recovered when returning to their conversation.

For the external task-control interface, see [Coding Agent integration](agent-mcp.md).
