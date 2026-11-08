defmodule EvoGit.Agents.SelfReflectiveTest do
  @moduledoc """
  Pins the repo-less Assistant's action surface.

  The Assistant drives Genesis ONLY through the shared task-control catalog
  (`genesis_*`), never through source reading or `elixir_eval`, so these tests
  assert the offered tool set, the dynamically rendered catalog in the persona
  prompt, and the dispatcher contracts those tool names rely on. No scheduler,
  approval service or application environment is mutated; the config directory
  is isolated per process, so the module is async-safe.
  """
  use ExUnit.Case, async: true

  alias EvoGit.Agent.Tools
  alias EvoGit.Agents.SelfReflective
  alias EvoGit.TaskControl.Tools, as: Catalog
  alias EvoGit.TestSupport.ConfigDir

  @genesis_tools ~w(
    genesis_check
    genesis_reload_config
    genesis_start_task
    genesis_get_task
    genesis_list_tasks
    genesis_list_models
    genesis_get_result
    genesis_send_message
    genesis_cancel_task
  )

  @retired_tools ~w(
    elixir_eval
    read
    rg
    glob
    list_dir
    read_context
    search_context
    search_history
  )

  setup do
    ConfigDir.isolate!("self-reflective-agent")
    :ok
  end

  test "available_tools/0 offers the task-control catalog plus the web tools only" do
    names = Enum.map(SelfReflective.available_tools(), &EvoGit.Agent.tool_name/1)

    expected = @genesis_tools ++ ["web_fetch"]
    # Web search depends on the host's configured search provider, so it is
    # allowed to appear but is never required.
    expected = if "web_search" in names, do: expected ++ ["web_search"], else: expected

    assert Enum.sort(names) == Enum.sort(expected)
    assert length(names) == length(Enum.uniq(names))

    for retired <- @retired_tools do
      refute retired in names,
             "expected #{inspect(retired)} to be absent from the repo-less assistant's tools"
    end
  end

  test "system_prompt/0 renders the live catalog and no retired surface" do
    prompt = SelfReflective.system_prompt()

    # Rendered from `EvoGit.TaskControl.Tools.list/0` at prompt-build time, so
    # every catalog name AND description must appear verbatim.
    for %{name: name, description: description} <- Catalog.list() do
      assert prompt =~ "- `#{name}` — #{description}"
    end

    refute prompt =~ "elixir_eval"
    refute prompt =~ "read_context"
  end

  test "genesis_get_task carries a 30 second default dispatch timeout" do
    assert Tools.default_timeout_ms("genesis_get_task") == 30_000
  end

  test "every catalog tool is dispatched as a non-write call" do
    for name <- @genesis_tools do
      refute Tools.write_call?(name, %{}),
             "expected #{inspect(name)} to be classified as a non-write call"
    end
  end
end
