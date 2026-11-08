# Retest Genesis from DeepSeek Harness on Windows

Use the [MCP preview](https://github.com/WLS2002/genesis/tree/mcp-preview-0.6.1) and follow [INSTALL.md](../INSTALL.md). The service and portable Skill work with an HTTP MCP host that supports authorization headers. Codex is optional.

## Preserve the previous experiment

Keep the previous report, result branches and unfinished worktrees. Copy unfinished tracked and untracked files outside `.genesis/workers` before replacing an older host. Do not use those files as the new task's implementation baseline. Stop only the identified Genesis host after checking its tasks; preserve the model, credentials and MCP token files.

The service version, target project commit, Skill version and Harness version are four separate values. Record all four. A service upgrade does not repair tests in an old target checkout. Use the current preview as the target baseline so its test isolation fixes are present; the GUI assistant entry remains the development task to be tested.

## Install and establish the exact runtime

In PowerShell, from the selected checkout:

```powershell
$env:GENESIS_VERSION = "mcp-preview-0.6.1"
$env:GENESIS_DOWNLOAD_BASE = "https://github.com/WLS2002/genesis/releases/download"
$env:GENESIS_DOWNLOAD_FALLBACK_BASE = "https://github.com/WLS2002/genesis/releases"
python scripts/setup-genesis.py --method release --json
```

The response supplies the running build identity, service URL, private MCP configuration path and portable Skill path. Register the connection in Harness and load the Skill. Keep the token in private host configuration. Model setup uses the reported service-side config/credentials paths; no Genesis page is required. Setup exit code `2` means model configuration still needs input, `0` means it is configured, and `1` means setup failed. None of these checks sends a model request.

On subsequent upgrades, add `--upgrade`. This requires a matching ownership record and no pending/running/finalizing/cancelling tasks. The installer keeps a rollback copy outside the runtime and restores the prior installation if the candidate fails. A host installed before ownership records existed must be identified and stopped explicitly before reinstalling. Custom installation paths need the same `--release-dir` on the next invocation.

Call `genesis_check` and compare `build.revision` with this tag's commit and the package's build-info JSON. A reachable port and a newly cloned checkout are insufficient evidence of a new running service. Preserve the original model/account/generation settings for comparison. Check that the Genesis process can find the target project's Git, Elixir 1.20.4+ and OTP 29 toolchain; the runtime bundled with Genesis runs the service but does not install a project development toolchain. Restart Genesis after changing the host PATH.

Before submitting a development task, privately record filenames and hashes in the service's configuration directory. Keep backups local and exclude credential contents from the report.

## Run small checks before the full objective

Use disposable projects for stop and interruption checks. These checks may invoke the selected model as part of the explicitly requested retest; record its usage separately from the main task.

1. Confirm that a multiline shell command returns both output lines and an exit code through Genesis. Record shell identity and command form if output is empty. Check stdout and stderr separately where available.
2. Run the target's configuration isolation regressions. Compare the real configuration directory's file set and hashes before and after. Do not run an older checkout's unsafe suite against the real host configuration.
3. Run a short task with a child agent. Query `genesis_get_task` and read `progress.report`: current work, reported outcomes, remaining work, blockers and next steps. Updates must continue while the root waits. An unchanged timestamp or elapsed time alone is not new progress.
4. Send a message to the root, then to a live child with `agent_id`. Save each `message_id`. `queued` is acceptance, `delivered` means context injection, and `unknown` means delivery cannot be established. Delivery does not mean the agent complied.
5. Cancel a disposable long task with `wait_seconds: 20`. Require `stopped: true` before handling its files. If graceful cancellation does not converge, use `force: true` for that task and check again. Unknown observations are returned as unknown, not proof that the task stopped.
6. Check that uncommitted files and unique partial commits remain recoverable after cancellation. On a separate disposable task, stop/restart the host and start another task in the same project. Retained work must survive. `recoverable_work` and `.genesis/recovery` identify preserved paths.
7. For the shared progress feature's product check, optionally compare the task page with the MCP report. A normal Harness user does not need the page. Reconnect both clients and confirm that the last saved progress remains visible.

## Repeat the original development objective

Reuse the original report's appendix A objective, keeping its product behavior and acceptance criteria. Update environment assumptions and paths that changed in the upstream merge. In particular, the latest agent protocol completes a run with a tool-free response; do not reintroduce the retired `complete_task` tool. Intermediate reporting uses the internal `report_progress` tool. Ask Genesis to implement the assistant entry, rather than preimplementing its backend/UI in Harness.

Use the same model as the prior experiment. Record the effective budget returned at submission. The initial MCP defaults are 6 total agents, depth 2, 96 root turns, 64 child turns and 2700 seconds, with bounded stop recovery after exhaustion. Choose explicit limits before the experiment if that objective needs more; do not silently raise them mid-run. Agent totals cover multiple root phases and retries do not reset a budgeted agent's consumed turns.

Follow with `since`, `wait_seconds` and `include_result: false`. Transfer the returned `change_token` into the next call. Normal queries include a short objective preview; request `include_objective: true` only when the full objective is needed. Report meaningful outcomes and blockers in Harness, and use targeted messages for corrections. Read results after a terminal state, including partial results and recoverable work after failure/cancellation.

## Keep evidence for success and failure

Record the task ID, four version identities, model/account settings without secrets, effective budget, start time, first substantive commit, completion/stop time, and cold dependency/build time. Preserve representative progress revisions, message receipts, cancellation responses, result branches and retained paths. Count compression and reads separately from cumulative provider usage; do not sum parent and child cumulative figures or treat the context token counter as total spend.

Keep exact test commands and outputs and compare the configuration directory's hashes. For malformed tool arguments, save the sanitized tool name, argument shape and finish reason. For shell output problems, save the command form, shell, stdout/stderr and exit code. Exclude prompts containing credentials, authentication files and tokens.

The original provider-specific malformed-argument and Windows empty-output incidents need this new trace to establish their cause. Native regressions check argument-error containment and multiline shell output; they do not prove the original provider trace was repaired. Likewise, budgets and better handoff/reporting need a real run to measure their effect on repeated reading and compression. A task stopped within budget with preserved work is a reliability result; the original feature succeeds only when its acceptance checks pass.
