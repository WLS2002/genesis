defmodule EvoDashWeb.HomeLive.SessionList do
  @moduledoc """
  Small, node-scoped summaries for the assistant's existing in-memory history.

  Passing the full `{node_id, resolved_node}` scope keeps two connection
  profiles distinct. An unresolved remote scope cannot expose local chats.
  Legacy states without a selection scope are admitted only on the local node.
  """

  use Gettext, backend: EvoDashWeb.Gettext

  alias EvoDash.{ChatHistory, SafeCall}

  @title_length 64
  @statuses [:idle, :running, :pending, :finalizing, :cancelling, :completed, :failed, :cancelled]

  @spec entries(term(), term()) :: [map()]
  def entries(current_id, target) do
    case normalize_target(target) do
      nil ->
        []

      scope ->
        SafeCall.run(
          fn ->
            ChatHistory.list_chats()
            |> Enum.take(10)
            |> Enum.flat_map(fn id ->
              case ChatHistory.get_state(id) do
                nil when id == current_id ->
                  if local_scope?(scope), do: [summary(id, %{}, current_id)], else: []

                state when is_map(state) ->
                  if same_scope?(state, scope), do: [summary(id, state, current_id)], else: []

                _ ->
                  []
              end
            end)
          end,
          []
        )
    end
  end

  defp normalize_target({nil, target_node}) when target_node == node(),
    do: {:scope, {nil, target_node}}

  defp normalize_target({id, target_node})
       when is_binary(id) and id != "" and is_atom(target_node) and
              target_node not in [nil, true, false] do
    if target_node != node(), do: {:scope, {id, target_node}}
  end

  defp normalize_target(target_node)
       when is_atom(target_node) and target_node not in [nil, true, false],
       do: {:node, target_node}

  defp normalize_target(_), do: nil

  defp local_scope?({:scope, {nil, target_node}}), do: target_node == node()
  defp local_scope?({:node, target_node}), do: target_node == node()
  defp local_scope?(_), do: false

  defp same_scope?(%{model_selection_scope: {id, target_node}}, {:scope, scope}),
    do: {id, target_node} == scope

  defp same_scope?(%{model_selection_scope: {id, target_node}}, {:node, target_node}) do
    if target_node == node(), do: is_nil(id), else: is_binary(id) and id != ""
  end

  defp same_scope?(state, scope) do
    not Map.has_key?(state, :model_selection_scope) and local_scope?(scope) and
      Map.get(state, :chat_node) in [nil, node()]
  end

  defp summary(id, state, current_id) do
    %{
      id: id,
      title: title(state),
      workspace: workspace(Map.get(state, :workspace)),
      status: status(state),
      current?: id == current_id
    }
  end

  defp title(state) do
    first_user =
      case Map.get(state, :transcript) do
        entries when is_list(entries) ->
          Enum.find_value(entries, fn
            %{role: role, text: text} when role in [:user, "user"] and is_binary(text) ->
              if String.trim(text) != "", do: text

            _ ->
              nil
          end)

        _ ->
          nil
      end

    text = first_user || binary_or_empty(Map.get(state, :chat_draft))
    text = text |> String.replace(~r/\s+/u, " ") |> String.trim()

    cond do
      text == "" -> gettext("New chat")
      String.length(text) > @title_length -> String.slice(text, 0, @title_length) <> "…"
      true -> text
    end
  end

  defp workspace(path) when is_binary(path) and path != "", do: path
  defp workspace(_), do: nil
  defp binary_or_empty(text) when is_binary(text), do: text
  defp binary_or_empty(_), do: ""

  defp status(state) do
    candidate = Map.get(state, :chat_task_status) || Map.get(state, :chat_status)
    if candidate in @statuses, do: candidate, else: :idle
  end
end
