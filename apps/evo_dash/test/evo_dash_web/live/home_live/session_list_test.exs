defmodule EvoDashWeb.HomeLive.SessionListTest do
  use ExUnit.Case, async: false

  alias EvoDash.ChatHistory
  alias EvoDashWeb.HomeLive.SessionList

  setup do
    ChatHistory.reset()
    Gettext.put_locale(EvoDashWeb.Gettext, "en")
    on_exit(fn -> ChatHistory.reset() end)
    :ok
  end

  test "summaries are newest first with a user title and no transcript body" do
    first =
      saved(%{transcript: [%{role: :user, text: "  Fix\n login   flow "}], workspace: "/repo"})

    second = saved(%{chat_draft: "Next task", chat_status: :running})

    assert [newer, older] = SessionList.entries(second, {nil, node()})
    assert newer.id == second
    assert newer.title == "Next task"
    assert newer.status == :running
    assert newer.current?
    assert older.id == first
    assert older.title == "Fix login flow"
    assert older.workspace == "/repo"
    refute older.current?
    refute Map.has_key?(older, :transcript)
    refute Map.has_key?(older, :thought_process)
  end

  test "system and assistant messages are not used as the session title" do
    id =
      saved(%{
        transcript: [
          %{role: :system, text: "SECRET PREFIX"},
          %{role: :assistant, text: "response"}
        ],
        chat_draft: "Draft title"
      })

    assert [%{id: ^id, title: "Draft title"}] = SessionList.entries(id, node())
  end

  test "long Unicode titles are bounded by graphemes" do
    saved(%{chat_draft: String.duplicate("界", 100)})
    assert [%{title: title}] = SessionList.entries(nil, node())
    assert String.valid?(title)
    assert String.length(title) <= 65
  end

  test "an untouched current session still has a readable title" do
    id = ChatHistory.new_chat()
    assert [%{id: ^id, title: "New chat", current?: true}] = SessionList.entries(id, node())
  end

  test "remote scope never borrows local or another target's sessions" do
    local = saved(%{chat_draft: "local"})
    remote = saved(%{model_selection_scope: {"remote-a", :remote_a@host}, chat_draft: "remote"})
    saved(%{model_selection_scope: {"remote-b", :remote_a@host}, chat_draft: "other account"})

    assert [%{id: ^remote}] = SessionList.entries(remote, {"remote-a", :remote_a@host})
    assert [%{id: ^local}] = SessionList.entries(local, {nil, node()})
    assert [] == SessionList.entries(local, {"pending", node()})
    assert [] == SessionList.entries(local, nil)
  end

  test "legacy state is shown only for clearly local conversations" do
    local = saved(%{chat_node: node(), chat_draft: "old local"})
    saved(%{chat_node: :other@host, chat_draft: "old remote"})
    saved(%{model_selection_scope: :malformed, chat_draft: "invalid scope"})

    assert [%{id: ^local}] = SessionList.entries(local, {nil, node()})
    assert [] == SessionList.entries(local, {"remote", :other@host})
  end

  test "malformed persisted state remains harmless and does not leak content" do
    id = ChatHistory.new_chat()
    ChatHistory.put_state(id, "private obsolete format")
    assert [] == SessionList.entries(id, node())
    assert [] == SessionList.entries(id, {:bad, nil})
  end

  defp saved(state) do
    id = ChatHistory.new_chat()
    ChatHistory.put_state(id, state)
    id
  end
end
