---
name: genesis
description: Delegate substantial development to Genesis, or honor an explicit request to use it. Also use to install or repair a Genesis connection, continue a task, inspect progress/results, or stop it.
---

# Develop with Genesis

Genesis is a development engine with its own configured models and background runtime. The calling agent supplies requirements, follows work and verifies the returned changes. Complete installation, configuration and task operations in the calling agent using MCP and the host terminal. The Genesis GUI is optional.

For the delegation decision, caller/engine responsibilities, a requirements handoff template, or Git/result expectations, read [overview](references/overview.md). For missing tools, installation, service failures or model readiness problems, read [setup](references/setup.md); it is usable from an installed plugin without assuming repository files are present. Prefer local execution for a known small edit unless the user explicitly asks for Genesis.

## Submit development

1. Establish the absolute local project directory and the user's goal, constraints and acceptance criteria. Include the relevant findings from this conversation in the objective; Genesis does not inherit your conversation. For a substantial handoff, use the [objective template](references/overview.md#handoff).
2. Call `genesis_check` for that path. If the service or models are not ready, follow [setup](references/setup.md) and resolve the reported issue before submitting. Genesis uses its configured models, not the calling agent's model automatically. Readiness checks inspect configuration without paid provider requests.
3. Call `genesis_start_task`: use `evolve` / `simple` for an existing project; use `genesis` / `new` for a new project in an existing directory. Follow the project's current Genesis prerequisites and Git behavior. The service does not snapshot uncommitted work or automatically apply results to the caller's working files.
4. Save the returned task ID and tell the user what was submitted. Offer `links.task` as an optional browser view while continuing to report progress yourself. `links.agents` is the general Agent inspector. For `links.access=open_on_genesis_host`, explain that the URL opens on the machine running Genesis; do not imply a phone or remote computer can reach its localhost. An accepted/running task is not a completed implementation.
5. Follow the task with `genesis_get_task`, using `include_result=false` for routine progress checks. Read `progress` for actual agent counts, scheduler statuses and activity counters. Save `progress.change_token`; the next call may pass it as `since` with `wait_seconds=20` to wait for a change. When `changed=false`, wait before checking again. Tools show observations, not a completion percentage or proof of a stall.
6. Report meaningful changes: work beginning, active agents making progress, failures, cancellation, and completion. If the task runs for a long time, briefly report the latest observed activity even when there is no major milestone. Avoid narrating every poll. A waiting scheduler state alone does not establish its cause; explain only what the data supports. If `scheduler_available=false`, say live observation is unavailable while preserving the saved task status.
7. When the task ends, call `genesis_get_result`. Read the saved report, errors and actual commit/branch locations, and share the task link. Distinguish the engine's test claims (`verification=not_independently_verified`) from checks you perform yourself. Inspect the changes and relevant evidence before claiming a verified outcome. Integration follows the user's normal review/merge workflow.

## Models and mid-task changes

Use `genesis_list_models` when the user wants a specific model or asks what is available. Choose only a returned profile ID; preserve the configured default otherwise. Model discovery does not test provider connectivity.

Use `genesis_send_message` for additional instructions while a task is running. Pass the task ID and the user's message; the server targets the live root agent. Report `queued_for_next_turn` as queued, not read/applied. Children already working are not automatically updated. If no root is runnable or the task has ended, inspect status and discuss a follow-up task rather than silently resubmitting the whole objective.

## Reconnect, continue or stop

- After a disconnected or uncertain submission, use `genesis_list_tasks` filtered by the project and inspect matching tasks before submitting again. A lost response does not mean the task failed to start.
- For follow-up work, start an `evolve` task with `resume_from` pointing to a finished task in the same project. This creates a new task using the previous task's saved context; it does not resume a live process or queue a message into it.
- When asked to stop, call `genesis_cancel_task` and inspect the status. `cancelling` is still in progress. Cancellation does not undo changes.

## Setup

Follow the portable [setup reference](references/setup.md) to locate the source checkout and select the current host's adapter. For missing models, authentication or edited configuration, follow [file and CLI configuration](references/configuration.md): use the server-reported paths, let the user fill private credentials locally or complete vendor login, then call `genesis_reload_config` and recheck. Reload the host connection if the tools are absent. Keep tokens out of messages and repository files.
