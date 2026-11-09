defmodule EvoGit.Agent.RunnerRepoLessTest do
  use ExUnit.Case, async: false
  alias EvoGit.AgentScheduler.{AgentState, Store}

  defmodule ToolBoundaryProbe do
    def system_prompt, do: "Task-control assistant probe"
    def delegation_level, do: :low
    def agent_type, do: :read
    def subagent_modules, do: []
    def available_tools, do: throw(:tool_boundary_reached)
  end

  @tag :tmp_dir
  test "real runner reaches tool construction without loading cwd context or skills", %{
    tmp_dir: dir
  } do
    File.write!(Path.join(dir, "CONTEXT.md"), "# Launch directory\nPRIVATE_LAUNCH_CONTEXT\n")
    id = 9_994_000 + System.unique_integer([:positive])
    spec = EvoGit.Runtime.SelfReflective.build_spec("Discuss the task", task_tmpdir: dir)

    :ok =
      Store.put_agent_state(id, %AgentState{
        context_node: spec.context_node,
        llm_model: "openai:gpt-4o-mini",
        max_turns: 8,
        max_retries: 0,
        max_depth: 2
      })

    on_exit(fn -> Store.delete_agent_state(id) end)
    Code.ensure_loaded!(EvoGit.Skills)
    session = :trace.session_create(:repo_less_skill_loading, self(), [])

    try do
      worker =
        Task.async(fn ->
          receive do
            :run ->
              try do
                EvoGit.Agent.Runner.run(ToolBoundaryProbe, "Discuss the task",
                  agent_id: id,
                  depth: 0,
                  repo_root: dir,
                  repo_id: "primary",
                  worktree_path: nil,
                  retries: 0,
                  spec: spec,
                  meta: %{task_id: nil},
                  repo_less: true,
                  repo_less_repo_path: dir
                )
              catch
                :throw, value -> value
              end
          end
        end)

      :trace.process(session, worker.pid, true, [:call])
      assert :trace.function(session, {EvoGit.Skills, :load_skills, 1}, true, [:local]) > 0
      send(worker.pid, :run)
      assert Task.await(worker) == :tool_boundary_reached
      barrier = :trace.delivered(session, :all)
      refute skill_load_seen?(barrier, false)
      {:ok, state} = Store.get_agent_state(id)
      refute inspect(state.context) =~ "PRIVATE_LAUNCH_CONTEXT"
    after
      :trace.session_destroy(session)
    end
  end

  defp skill_load_seen?(barrier, seen) do
    receive do
      {:trace_delivered, :all, ^barrier} -> seen
      {:trace, _, :call, {EvoGit.Skills, :load_skills, _}} -> skill_load_seen?(barrier, true)
    after
      5000 -> flunk("trace barrier did not complete")
    end
  end
end
