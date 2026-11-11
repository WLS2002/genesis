defmodule EvoDashWeb.HomeLive.WorkspaceTest do
  use ExUnit.Case, async: false

  alias EvoDashWeb.HomeLive.Workspace

  setup do
    root =
      Path.join(System.tmp_dir!(), "assistant-workspace-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    on_exit(fn ->
      EvoDash.SafeCall.run(fn -> EvoDash.NodeContext.forget_project(node(), root) end)
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "opens and remembers an existing directory without creating a task", %{root: root} do
    assert {:ok, ^root, projects} = Workspace.open(nil, node(), "  #{root}  ")
    assert Enum.any?(projects, &(&1.path == root))
  end

  test "rejects relative and blank paths without resolving against server cwd" do
    assert {:error, message} = Workspace.open(nil, node(), "relative/project")
    assert is_binary(message)
    assert {:error, _} = Workspace.open(nil, node(), "  ")
  end

  test "does not create a missing directory", %{root: root} do
    missing = Path.join(root, "missing")
    assert {:error, _} = Workspace.open(nil, node(), missing)
    refute File.exists?(missing)
  end

  test "does not accept a regular file as a workspace", %{root: root} do
    file = Path.join(root, "README.md")
    File.write!(file, "example")
    assert {:error, _} = Workspace.open(nil, node(), file)
  end

  test "a pending remote target cannot use the local node's filesystem", %{root: root} do
    assert {:error, _} = Workspace.open("remote-pending", node(), root)
    assert {:error, _} = Workspace.open("remote-pending", nil, root)
  end

  test "an unavailable remote node yields an error rather than local success", %{root: root} do
    assert {:error, _} = Workspace.open("offline", :assistant_offline@invalid, root)
  end

  test "malformed inputs produce a usable error" do
    assert {:error, message} = Workspace.open(nil, node(), nil)
    assert is_binary(message)
  end
end
