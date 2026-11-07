# Working with Genesis

## Caller and engine

Genesis is a local development engine with its own model profiles, task history, agents and Git worktrees. The calling agent is the user's coordinator: it gathers requirements, submits a bounded objective through MCP, follows progress, and inspects the result. Genesis plans and executes the development inside its runtime. The caller remains responsible for explaining the outcome and checking evidence before calling it verified.

Use delegation for a feature spanning several modules, a substantial investigation/refactor, or work that benefits from Genesis's agent coordination and background execution. A known one-file edit is usually quicker in the caller's workspace. Honor an explicit request to use Genesis even for a small task, subject to the host's available tools and authorization.

Genesis's model is configured separately from the caller's model. A Codex subscription login may be usable through Genesis's existing subscription profile support, but installing this plugin does not select the caller's model or transfer conversation state. Use returned profile IDs from `genesis_list_models` when a particular model is requested; otherwise preserve the configured default. A readiness check reads configuration and does not make a paid provider call.

## Handoff

Genesis receives the objective and project location you supply, plus context its own runtime reads from the project. It does not inherit the caller's conversation, discoveries or unstored requirements. Before `genesis_start_task`, turn the relevant conversation into a self-contained objective. Include file references and observed evidence when useful; omit credentials and unrelated history.

Use this shape, adapting it to the task:

```text
Outcome: What should the user be able to do when this is finished?
Project: Absolute path, existing/new project, relevant branch and starting state.
Scope: Components or files involved; explicit boundaries.
Constraints: Existing behavior, APIs, design decisions and user preferences to preserve.
Findings: Relevant code locations, observations, prior attempts and their evidence.
Acceptance: Observable behavior and the checks that establish it.
Delivery: Expected result/report; existing review and integration requirements.
```

If a requirement would materially change the objective and cannot be inferred from available context, settle it before submission. Routine implementation choices can remain with Genesis. Keep the returned task ID for later calls and reconnection.

## Background work and visibility

Once accepted, the task belongs to the Genesis service. It continues independently of the caller's HTTP request or host session while that service remains running. Closing the calling session is not cancellation. Use `genesis_cancel_task` when the user asks to stop; inspect until the task reaches a terminal state.

Report actual progress from `genesis_get_task`: status, agent counts and activity changes. The user can stay in the calling agent for the full workflow. Offer `links.task` for the task Review page and `links.agents` for the general Agent inspector as optional views. A localhost link with `links.access=open_on_genesis_host` opens on the Genesis machine. Use bounded waits with the previous change token; a quiet interval or waiting agent alone does not explain a stall. Keep the user informed during long work without narrating each poll. Additional instructions can be queued with `genesis_send_message`; its acknowledgement means queued for the root's next turn, not that every agent has read or applied them.

## Results and existing Git behavior

An accepted task or a successful engine report is not independent verification. When terminal, read `genesis_get_result`, inspect saved errors and the actual commit/branch fields, then inspect the reported changes and run the checks relevant to the user's acceptance criteria. Distinguish engine-reported validation from checks you performed yourself. Failed or cancelled tasks may still have partial outcomes worth inspecting.

The connector uses Genesis's existing Git behavior: candidate changes may live in task worktrees and result branches. It adds no snapshot of uncommitted caller files and no automatic application to the caller's working tree. Determine the starting branch and dirty state before handing off; inspect the returned location before integration. Preserve other work and follow the user's normal commit, review and merge requirements. A task result alone does not authorize a merge, push or deployment.

Existing repositories need an initial commit and a primary checkout with a `.git` directory for this entry point. Linked worktree and submodule roots are rejected by readiness checks. For follow-up development, `resume_from` creates a new `evolve` task using a finished task's saved context in the same project; it does not revive the old process.
