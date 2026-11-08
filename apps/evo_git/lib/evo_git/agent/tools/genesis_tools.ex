defmodule EvoGit.Agent.Tools.GenesisTools do
  @moduledoc """
  The `genesis_*` task-control tools, as the repo-less Genesis Assistant calls
  them.

  The catalog itself lives in `EvoGit.TaskControl.Tools` — the single source
  shared with the MCP endpoint. This module is only the MODEL-FACING adapter:
  it turns a catalog result into the plain binary that a tool result must be,
  so the assistant can inspect and drive tasks through exactly the same
  contract external MCP callers use.
  """

  alias EvoGit.TaskControl.Tools

  @doc """
  Executes one `genesis_*` tool call and returns the model-facing text.

  Successes are pretty-printed JSON; failures are `Error: …` strings (an
  `invalid` call keeps the message bare, a task-control error is rendered as
  JSON). Never raises on a catalog-level failure.
  """
  @spec execute(term(), term()) :: String.t()
  def execute(name, args) do
    case Tools.call(name, args) do
      {:ok, data} -> Jason.encode!(data, pretty: true)
      {:invalid, message} -> "Error: #{message}"
      {:error, error} -> "Error: " <> Jason.encode!(error)
    end
  end
end
