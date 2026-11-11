defmodule EvoGit.TaskControl.ToolsTest do
  use EvoGit.TaskRegistryCase, async: true

  alias EvoGit.Agent.Tools, as: AgentTools
  alias EvoGit.TaskControl.Tools, as: Catalog

  test "the repo-less assistant route reads the registry result through shared task control" do
    :ok =
      EvoGit.Store.put_task(store(), %EvoGit.TaskInfo{
        id: "assistant-result",
        type: :evolve,
        status: :completed,
        opts: [objective: "Fixture task"],
        result: {:ok, %{result: "Saved task report"}}
      })

    Process.put(:repo_less, true)

    for args <- [%{"task_id" => "assistant-result"}, ~s({"task_id":"assistant-result"})] do
      result =
        AgentTools.execute("genesis_get_result", args, "[system]", "[system]", "./")
        |> Jason.decode!()

      assert result["id"] == "assistant-result"
      assert result["status"] == "completed"
      assert result["summary"] == "Saved task report"
      refute Map.has_key?(result, "opts")
    end

    assert {:ok, %{summary: "Saved task report"}} =
             Catalog.call("genesis_get_result", %{"task_id" => "assistant-result"})
  end

  test "the assistant adapter preserves missing-task errors and validates calls through the catalog" do
    Process.put(:repo_less, true)

    assert {:error, %{code: "not_found"}} =
             Catalog.call("genesis_get_task", %{"task_id" => "missing"})

    text =
      AgentTools.execute(
        "genesis_get_task",
        %{"task_id" => "missing"},
        "[system]",
        "[system]",
        "./"
      )

    assert "Error: " <> error = text
    assert Jason.decode!(error)["code"] == "not_found"

    invalid =
      AgentTools.execute(
        "genesis_start_task",
        %{"path" => "relative", "objective" => "Do not submit"},
        "[system]",
        "[system]",
        "./"
      )

    assert invalid =~ "Error:"
    assert TaskRegistry.list_tasks() == []
  end
end
