defmodule EvoGit.SelfReflectiveToolsTest do
  @moduledoc """
  Pins the assistant's public tool/persona contract without running an agent or
  evaluating code: the tool set and the Genesis-operator system prompt (role,
  the dynamically rendered task-control catalog, workspace handling, task
  lifecycle guidance and the finish contract).

  The assistant's entire action surface is the shared task-control catalog
  `EvoGit.TaskControl.Tools` — the same tools the MCP endpoint exposes — so the
  prompt is asserted against the live catalog instead of a hand-copied list.
  ConfigDir isolation is per process; no scheduler, approval service or
  application environment is mutated, so these tests are async-safe.
  """
  use ExUnit.Case, async: true

  alias EvoGit.Agents.SelfReflective
  alias EvoGit.TaskControl.Tools
  alias EvoGit.TestSupport.ConfigDir

  setup do
    ConfigDir.isolate!("self-reflective-tools")
    :ok
  end

  defp prompt, do: SelfReflective.system_prompt()

  test "the assistant's whole action surface is the shared task-control catalog" do
    names = Enum.map(SelfReflective.available_tools(), & &1.name)

    catalog_tools = Enum.map(Tools.list(), & &1.name)

    expected =
      if EvoGit.Config.tools_search_enabled?() do
        catalog_tools ++ ["web_fetch", "web_search"]
      else
        catalog_tools ++ ["web_fetch"]
      end

    assert Enum.sort(names) == Enum.sort(expected)
    assert length(names) == length(Enum.uniq(names))

    # The retired source-reading and evaluation surface is gone.
    for retired <- ~w(elixir_eval read rg glob list_dir read_context search_context search_history
                      write edit bash run_command run_git) do
      refute retired in names, "retired tool #{retired} is still offered"
    end

    assert SelfReflective.agent_type() == :read
    assert SelfReflective.delegation_level() == :low
    assert SelfReflective.subagent_modules() == []
  end

  test "the persona renders every catalog tool from the live catalog, name and description" do
    rendered = prompt()

    assert Enum.count(Tools.list()) == 9

    for %{name: name, description: description} <- Tools.list() do
      assert rendered =~ "- `#{name}` — #{description}",
             "the prompt must render #{name} from EvoGit.TaskControl.Tools.list/0"
    end

    assert rendered =~ "web_fetch"
  end

  test "the persona speaks AS Genesis in the first person and mirrors the user's language" do
    rendered = prompt()

    assert rendered =~ "you speak AS Genesis"
    assert rendered =~ "in the first person"
    assert rendered =~ "never as an outside narrator"
    assert rendered =~ "answer in the user's language"
  end

  test "the persona states the repo-less situation and that the catalog is its only action surface" do
    rendered = prompt()

    assert rendered =~ "You are repo-less"
    assert rendered =~ "no repository and no worktree"
    assert rendered =~ "produces no commits"
    assert rendered =~ "shared Genesis task-control catalog"
    assert rendered =~ "the very same tools the MCP endpoint exposes"
    assert rendered =~ "Every effect you have on the world goes through the task-control tools"
  end

  test "the persona explains Genesis as a background engine whose branches the user merges" do
    rendered = prompt()

    assert rendered =~ "Genesis is a background development engine"
    assert rendered =~ "isolated git worktree"
    assert rendered =~ "genesis/agent_*"
    assert rendered =~ "you never merge or push"
  end

  test "the persona uses a ## Workspace path and otherwise asks for an absolute path" do
    rendered = prompt()

    assert rendered =~ "## Workspace"
    assert rendered =~ "pass its path value exactly as the `path` argument"
    assert rendered =~ "genesis_start_task"
    assert rendered =~ "genesis_list_tasks"
    assert rendered =~ "genesis_check"
    assert rendered =~ "ask the user for an absolute project path"
    assert rendered =~ "Never guess"
  end

  test "the persona discusses the approach before starting a task" do
    rendered = prompt()

    assert rendered =~ "Discuss the approach first"
    assert rendered =~ "Call `genesis_start_task` only after the user explicitly agrees to start"
    assert rendered =~ "not authorizing a task"
  end

  test "the persona pins the objective, task-type and budget guidance for a new task" do
    rendered = prompt()

    assert rendered =~ "`objective` must be self-contained"
    assert rendered =~ "acceptance criteria"
    assert rendered =~ ~s(task_type: "evolve")
    assert rendered =~ ~s(mode: "simple")
    assert rendered =~ ~s(task_type: "genesis")
    assert rendered =~ ~s(mode: "new")
    assert rendered =~ "Pass `budget` for long-running work"
    assert rendered =~ "genesis_list_models"
  end

  test "the persona avoids duplicates and continues earlier work with resume_from" do
    rendered = prompt()

    assert rendered =~ "Call `genesis_list_tasks` first"
    assert rendered =~ "instead of submitting a second copy"
    assert rendered =~ "Read a finished task with `genesis_get_result`"
    assert rendered =~ "`resume_from`"
    assert rendered =~ "completed task in the same project"
  end

  test "the persona follows a task with since, wait_seconds and the result-first contract" do
    rendered = prompt()

    assert rendered =~ "`genesis_get_task`"
    assert rendered =~ "Pass `since` with the `progress.change_token`"
    assert rendered =~ "wait_seconds"
    assert rendered =~ "include_result: false"
    assert rendered =~ "Fetch the result only once the task is terminal"
    assert rendered =~ "`running` is NOT completion"
    assert rendered =~ "not independent verification"
  end

  test "the persona reports unavailable observation instead of inventing progress" do
    rendered = prompt()

    assert rendered =~ "scheduler_available: false"
    assert rendered =~ "observation is unavailable"
    assert rendered =~ "never invent progress"
  end

  test "the persona reports from tool output and never merges or pushes for the user" do
    rendered = prompt()

    assert rendered =~ "Report the status, what actually changed, how it was verified"
    assert rendered =~ "Take links and IDs only from what the tools returned"
    assert rendered =~ "never construct a URL or a task ID"
    assert rendered =~ "Never merge, push"
  end

  test "the persona pins graceful cancellation, force escalation and the stopped check" do
    rendered = prompt()

    assert rendered =~ "`genesis_cancel_task` stops a task gracefully"
    assert rendered =~ "results are kept"
    assert rendered =~ "Git changes are NOT rolled back"
    assert rendered =~ "force: true"
    assert rendered =~ "Always check `stopped`"
  end

  test "the persona configures only through genesis_check's paths and genesis_reload_config" do
    rendered = prompt()

    assert rendered =~ "Use only the `config_files` that `genesis_check` returns"
    assert rendered =~ "never invent configuration keys"
    assert rendered =~ "call `genesis_reload_config`"
  end

  test "the persona forbids fabrication and CLI hints and ends the run with a plain reply" do
    rendered = prompt()

    assert rendered =~ "Never invent a tool, an argument, a schema field or a task ID"
    assert rendered =~ "Never claim to have inspected code"
    assert rendered =~ "Never suggest terminal or CLI commands"
    assert rendered =~ "A reply with no tool calls ends your run"
    assert rendered =~ "There is no completion tool"
  end

  test "the persona no longer offers evaluation or source reading" do
    rendered = prompt()

    refute rendered =~ "elixir_eval"
    refute rendered =~ "read_context"
    refute rendered =~ "search_context"
    refute rendered =~ "Read the Genesis source"
    refute rendered =~ "source tree"
  end
end
