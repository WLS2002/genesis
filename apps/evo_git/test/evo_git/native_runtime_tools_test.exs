defmodule EvoGit.NativeRuntimeToolsTest do
  use ExUnit.Case, async: true
  @moduletag :tmp_dir

  test "consecutive native shell commands retain both outputs", %{tmp_dir: root} do
    result =
      EvoGit.Agent.Tools.ShellTool.execute(
        %{"command" => "echo genesis-first\necho genesis-second"},
        root,
        root
      )

    assert result =~ "genesis-first"
    assert result =~ "genesis-second"
    assert result =~ "[Exit Code: 0]"
  end
end
