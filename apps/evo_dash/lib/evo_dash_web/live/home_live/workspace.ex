defmodule EvoDashWeb.HomeLive.Workspace do
  @moduledoc """
  Opens an existing project directory for the assistant without leaving chat.

  Call from the page's supervised async loader: filesystem/store calls may be
  remote. A pending remote target never falls back to the dashboard filesystem.
  """

  use Gettext, backend: EvoDashWeb.Gettext

  alias EvoDash.{NodeContext, SafeCall}
  alias EvoDashWeb.ProjectsLive.ProjectFlow

  @spec open(String.t() | nil, node(), term()) ::
          {:ok, String.t(), [map()]} | {:error, String.t()}
  def open(node_id, target_node, input) when is_binary(input) do
    with :ok <- ready_target(node_id, target_node),
         {:ok, path} <- normalize_path(node_id, target_node, input),
         {:ok, true} <- SafeCall.run(fn -> NodeContext.dir?(target_node, path) end),
         {:ok, {:ok, %{path: ^path}}} <-
           SafeCall.run(fn ->
             NodeContext.mount_project(target_node, path, Path.basename(path))
           end),
         {:ok, projects} when is_list(projects) <-
           SafeCall.run(fn -> NodeContext.projects(target_node) end) do
      projects =
        Enum.filter(projects, fn
          %{path: project_path} when is_binary(project_path) ->
            ProjectFlow.absolute_path_for_node?(target_node, project_path)

          _ ->
            false
        end)

      # Project listings degrade transport failures to []; only
      # claim a remembered project when the subsequent read confirms it.
      if Enum.any?(projects, &(&1.path == path)) do
        {:ok, path, projects}
      else
        {:error, gettext("Could not remember this project. Reconnect and try again.")}
      end
    else
      {:error, :unavailable} ->
        {:error, gettext("Connect to the selected node before choosing a project.")}

      {:error, reason} when reason in [:blank, :relative] ->
        {:error, gettext("Enter a full directory path.")}

      {:ok, false} ->
        {:error, gettext("This directory is unavailable on the selected node.")}

      _ ->
        {:error, gettext("Could not open this project. Check the directory and try again.")}
    end
  end

  def open(_, _, _), do: {:error, gettext("Enter a full directory path.")}

  defp ready_target(nil, target_node) when target_node == node(), do: :ok

  defp ready_target(id, target_node)
       when is_binary(id) and id != "" and is_atom(target_node) and
              target_node not in [nil, true, false] do
    if target_node != node() and target_node in Node.list(:connected),
      do: :ok,
      else: {:error, :unavailable}
  end

  defp ready_target(_, _), do: {:error, :unavailable}

  defp normalize_path(nil, _node, input), do: ProjectFlow.normalize_project_path(input)

  defp normalize_path(_id, target_node, input) do
    case SafeCall.run(fn -> ProjectFlow.normalize_remote_project_path(target_node, input) end) do
      {:ok, result} -> result
      {:error, _} -> {:error, :unavailable}
    end
  end
end
