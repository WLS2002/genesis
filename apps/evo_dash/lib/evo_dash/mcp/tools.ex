defmodule EvoDash.MCP.Tools do
  @moduledoc """
  Thin MCP-transport adapter over the shared task-control catalog.

  The nine `genesis_*` tools are described and dispatched ONLY by
  `EvoGit.TaskControl.Tools` (shared with the repo-less Genesis Assistant), so
  this module adds exactly what is MCP-specific: the wire-format
  `inputSchema`/`annotations` projection, browser-link enrichment and the
  `%{content, structuredContent, isError}` tool-result envelope.
  """
  alias EvoGit.TaskControl.Tools, as: Catalog

  def list do
    Enum.map(Catalog.list(), fn %{
                                  name: name,
                                  description: description,
                                  input_schema: input_schema,
                                  read_only: read_only
                                } ->
      %{
        name: name,
        description: description,
        inputSchema: input_schema,
        annotations: %{
          readOnlyHint: read_only,
          destructiveHint: not read_only,
          openWorldHint: false
        }
      }
    end)
  end

  def call(name, args) do
    case Catalog.call(name, args) do
      {:ok, data} -> {:ok, result(EvoDash.MCP.Links.enrich(data), false)}
      {:invalid, message} -> {:invalid, message}
      {:error, error} -> {:ok, result(%{error: error}, true)}
    end
  end

  defp result(data, failed) do
    %{
      content: [%{type: "text", text: Jason.encode!(data)}],
      structuredContent: data,
      isError: failed
    }
  end
end
