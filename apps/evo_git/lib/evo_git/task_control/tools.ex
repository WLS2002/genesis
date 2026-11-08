defmodule EvoGit.TaskControl.Tools do
  @moduledoc """
  The SINGLE task-control tool catalog, shared by both transports.

  `EvoDash.MCP.Tools` (the MCP endpoint) and the repo-less Genesis Assistant
  (`EvoGit.Agent.Tools.GenesisTools`) expose the SAME nine `genesis_*` tools to
  the model. The catalog lives here — in the core runtime — so both transports
  describe exactly the same names, descriptions, input schemas and
  read-only/write classifications, and dispatch through the same
  `EvoGit.TaskControl` boundary. Neither transport keeps a second copy.

  This module is a projection layer only: it validates the tool call shape and
  delegates to `EvoGit.TaskControl`, which owns argument validation and
  projection of JSON-safe task data. It never maintains task lifecycle state.
  """
  alias EvoGit.TaskControl

  @path %{type: "string", description: "Absolute project directory on the Genesis host."}
  @id %{type: "string", description: "Task ID returned by Genesis."}
  @tools [
    {"genesis_check", :check,
     "Check Genesis version, model readiness, configuration file paths on the Genesis host and optional project path. Does not test provider connectivity or apply file edits.",
     %{path: @path}, [], true},
    {"genesis_reload_config", :reload_config,
     "Validate and load edited Genesis configuration/credential files into the running scheduler, then return readiness. Takes no secrets or file contents. Does not restart existing agents or test provider connectivity; node distribution changes require a service restart.",
     %{}, [], false},
    {"genesis_start_task", :start,
     "Start background development; returns a task ID immediately. Existing Genesis Git behavior applies. Poll genesis_get_task for the actual result. To continue a finished task, use evolve with resume_from in the same project.",
     %{
       path: @path,
       budget: %{
         type: "object",
         additionalProperties: false,
         properties:
           Map.new(
             ~w(max_agents max_depth max_turns_root max_turns max_duration_seconds),
             &{&1, %{type: "integer", minimum: 1}}
           )
       },
       objective: %{
         type: "string",
         description: "Development goal, context, constraints and acceptance criteria."
       },
       task_type: %{type: "string", enum: ["evolve", "genesis"], default: "evolve"},
       mode: %{
         type: "string",
         enum: ["simple", "new", "existing"],
         description:
           "Allowed pairs: evolve/simple, genesis/new, genesis/existing. Omit mode to use simple for evolve or new for genesis."
       },
       resume_from: @id,
       model_id: %{type: "string", description: "Optional configured Genesis model profile ID."}
     }, ["path", "objective"], false},
    {"genesis_get_task", :get,
     "Read shared task progress (current work, reported outcomes, remaining work, blockers, next steps), activity and saved results. Full objectives are opt-in. Running is not completed; reports are not independent verification.",
     %{
       task_id: @id,
       since: %{
         type: "string",
         description: "Previous progress.change_token; unchanged active tasks may wait."
       },
       wait_seconds: %{type: "integer", minimum: 0, maximum: 20, default: 0},
       include_result: %{type: "boolean", default: true},
       include_objective: %{type: "boolean", default: false}
     }, ["task_id"], true},
    {"genesis_list_tasks", :list,
     "Find recent tasks, optionally filtered by absolute project path. Use after reconnecting instead of submitting duplicate work.",
     %{
       path: @path,
       limit: %{type: "integer", minimum: 1, maximum: 50, default: 20},
       offset: %{type: "integer", minimum: 0, maximum: 1_000_000, default: 0},
       status: %{
         type: "string",
         enum: ~w(pending running finalizing completed failed cancelled cancelling)
       },
       search: %{type: "string", description: "Search task goals, IDs and project paths."}
     }, [], true},
    {"genesis_list_models", :models,
     "List configured model profiles without credentials; use IDs with genesis_start_task.model_id.",
     %{}, [], true},
    {"genesis_get_result", :result,
     "Read a finished task's saved report, errors and result commits. Reports not_ready for active tasks. Test claims are backend-reported, not independently verified.",
     %{task_id: @id}, ["task_id"], true},
    {"genesis_send_message", :message,
     "Queue instructions to a running task's root or optional agent_id. Follow the message receipt: queued is not delivered, and delivered is not proof of adoption. The target must belong to this task.",
     %{task_id: @id, message: %{type: "string"}, agent_id: %{type: "integer", minimum: 1}},
     ["task_id", "message"], false},
    {"genesis_cancel_task", :cancel,
     "Request stopping, optionally wait up to 20 seconds or force escalation. Inspect stopped and recoverable_work; a terminal row alone does not confirm process cleanup. Does not undo Git changes.",
     %{
       task_id: @id,
       force: %{type: "boolean", default: false},
       wait_seconds: %{type: "integer", minimum: 0, maximum: 20, default: 0}
     }, ["task_id"], false}
  ]

  @doc """
  The catalog as transport-neutral descriptions.

  Each entry carries the STRING-keyed JSON Schema object
  (`%{"type" => "object", "properties" => ..., "required" => ...,
  "additionalProperties" => false}`) so any transport can hand it to a model
  verbatim, plus the `read_only` flag that decides whether the tool needs
  approval on a write-capable transport.
  """
  def list do
    Enum.map(@tools, fn {name, _function, description, properties, required, read_only} ->
      %{
        name: name,
        description: description,
        input_schema: %{
          "type" => "object",
          "properties" => string_keys(properties),
          "required" => required,
          "additionalProperties" => false
        },
        read_only: read_only
      }
    end)
  end

  @doc """
  Dispatches one catalog tool call to `EvoGit.TaskControl`.

  Returns `{:ok, data}` on success, `{:invalid, message}` for a malformed call
  (unknown tool, wrong call shape, or `TaskControl`'s `invalid_arguments`
  rejection) and `{:error, error}` for every other task-control failure (a
  task-control error map with `code`/`message` keys).
  """
  def call(name, args) when is_binary(name) and is_map(args) do
    case Enum.find(@tools, &(elem(&1, 0) == name)) do
      nil ->
        {:invalid, "Unknown tool: #{name}"}

      {_, function, _, _, _, _} ->
        case apply(TaskControl, function, [args]) do
          {:ok, data} -> {:ok, data}
          {:error, %{code: "invalid_arguments", message: message}} -> {:invalid, message}
          {:error, error} -> {:error, error}
        end
    end
  end

  def call(_, _), do: {:invalid, "Tool name must be a string and arguments must be an object."}

  @doc """
  The catalog as `ReqLLM` tool schemas, ready for a model request.

  Callbacks are inert placeholders (the transport dispatches through `call/2`),
  exactly like every other `EvoGit.Agent.Tools.*.schema/0`.
  """
  def reqllm_schemas do
    Enum.map(list(), fn %{name: name, description: description, input_schema: schema} ->
      ReqLLM.tool(
        name: name,
        description: description,
        parameter_schema: schema,
        callback: fn _ -> {:ok, nil} end
      )
    end)
  end

  # The catalog literals keep Elixir's atom-key shorthand; a JSON Schema handed
  # to a model must be STRING-keyed all the way down. Values are untouched.
  defp string_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), string_keys(nested)} end)
  end

  defp string_keys(value) when is_list(value), do: Enum.map(value, &string_keys/1)
  defp string_keys(value), do: value
end
