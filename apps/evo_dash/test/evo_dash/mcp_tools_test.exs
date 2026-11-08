defmodule EvoDash.MCP.ToolsTest do
  use ExUnit.Case, async: true

  alias EvoDash.MCP.Tools
  alias EvoGit.TaskControl.Tools, as: Catalog

  test "exposes the shared catalog's nine tools in order with identical metadata" do
    mcp_tools = Tools.list()
    core_tools = Catalog.list()

    assert length(mcp_tools) == 9
    assert Enum.map(mcp_tools, & &1.name) == Enum.map(core_tools, & &1.name)

    Enum.zip(mcp_tools, core_tools)
    |> Enum.each(fn {tool, core_tool} ->
      assert tool.name == core_tool.name
      assert tool.description == core_tool.description
      assert tool.inputSchema == core_tool.input_schema
    end)
  end

  test "annotations mirror the shared catalog's read_only classification" do
    Enum.zip(Tools.list(), Catalog.list())
    |> Enum.each(fn {tool, core_tool} ->
      assert tool.annotations == %{
               readOnlyHint: core_tool.read_only,
               destructiveHint: not core_tool.read_only,
               openWorldHint: false
             }
    end)
  end

  test "unknown tool names are invalid on both layers" do
    assert {:invalid, message} = Tools.call("genesis_no_such_tool", %{})
    assert message =~ "genesis_no_such_tool"
    assert {:invalid, _} = Catalog.call("genesis_no_such_tool", %{})
  end
end
