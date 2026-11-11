defmodule EvoDashWeb.HomeLiveRenderTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  # Exercise the real page template without mounting /help: a connected mount
  # writes the global ChatHistory hub and must not run in the async cohort.
  # These fixtures are presentation state only; no task or provider is started.
  defp page(overrides \\ []) do
    assigns = [
      flash: %{},
      current_node: node(),
      current_node_id: nil,
      current_node_name: "Local",
      running_tasks: [],
      pending_tasks: [],
      desktop_quit_confirm: false,
      update_status: nil,
      guide: nil,
      provider_profiles: [],
      model_selections: [],
      model_spec: %{},
      model_snapshot: %{node: node(), config: %{}},
      model_select_loading: false,
      model_select_load_error: nil,
      model_selection_error: nil,
      model_selection_enabled: false,
      source_available: true,
      source_busy: nil,
      transcript: [],
      chat_status: :idle,
      chat_task_status: nil,
      thought_process: [],
      raw_entry_ids: MapSet.new(),
      pending_approvals: [],
      approval_error: nil,
      chat_draft: "",
      workspace: "/work/project-a",
      chat_id: 1,
      workspace_open: false,
      workspace_form: Phoenix.Component.to_form(%{"path" => ""}),
      workspace_loading: false,
      workspace_error: nil,
      history_open: false,
      sessions: [],
      recent_projects: [
        %{path: "/work/project-a", name: "Project A"},
        %{path: "/work/project-b", name: "Project B"}
      ]
    ]

    render_component(&EvoDashWeb.HomeLive.render/1, Keyword.merge(assigns, overrides))
    |> Floki.parse_document!()
  end

  defp text(dom, selector), do: dom |> Floki.find(selector) |> Floki.text() |> String.trim()
  defp attr(dom, selector, name), do: dom |> Floki.find(selector) |> Floki.attribute(name)

  test "composer card renders the shared picker and rule-controlled Auto label" do
    profiles = [%{"id" => "work-account", "name" => "Work", "provider" => "openai"}]

    selections = [
      %{
        provider_profile_id: "work-account",
        model: "reasoned-model",
        reasoning_efforts: ["low", "high"],
        default_reasoning_effort: "low"
      }
    ]

    spec = %{
      "provider_profile_id" => "work-account",
      "model" => "reasoned-model",
      "reasoning_effort" => "high"
    }

    dom =
      page(
        provider_profiles: profiles,
        model_selections: selections,
        model_spec: spec,
        model_selection_enabled: true
      )

    # Fused-capsule root: the shared client hook owns the active panel view.
    assert attr(dom, "#chat-llm-selection", "phx-hook") == ["CapsulePanel"]
    assert attr(dom, "#chat-llm-selection", "data-capsule-view") == ["model"]

    # ONE panel with two sibling views (model + provider drill-down) — there is
    # no provider `<select>` and no `phx-change` anywhere in the picker.
    assert Floki.find(dom, "#chat-llm-selection .capsule-view[data-view='model']") != []
    assert Floki.find(dom, "#chat-llm-selection .capsule-view[data-view='provider']") != []
    assert Floki.find(dom, "#chat-llm-selection select") == []
    assert Floki.find(dom, "#chat-llm-selection [phx-change]") == []

    # The model view's drill row opens the provider list; the provider view's
    # back row returns to the model list.
    assert attr(dom, "#chat-llm-selection-provider", "data-capsule-drill") == ["provider"]
    assert attr(dom, "#chat-llm-selection-provider-list", "role") == ["listbox"]
    assert Floki.find(dom, "#chat-llm-selection .capsule-back[data-capsule-back]") != []

    assert attr(dom, "#chat-llm-selection-model .capsule-item[aria-selected='true']", "phx-click") ==
             [
               "select_model"
             ]

    assert attr(
             dom,
             "#chat-llm-selection-reasoning .capsule-stop[aria-pressed='true']",
             "phx-click"
           ) == [
             "select_reasoning_effort"
           ]

    # Provider inventory/selection lives in the drill-down provider list: the
    # selected row is the `aria-selected="true"` option carrying its profile id,
    # and the drill row shows that profile's display name.
    assert attr(
             dom,
             "#chat-llm-selection-provider-list [role='option'][aria-selected='true']",
             "phx-value-provider_profile_id"
           ) == ["work-account"]

    assert text(dom, "#chat-llm-selection-provider .capsule-drill-value") == "Work"

    assert attr(
             dom,
             "#chat-llm-selection-model .capsule-item[aria-selected='true']",
             "phx-value-model"
           ) == [
             "reasoned-model"
           ]

    assert attr(
             dom,
             "#chat-llm-selection-reasoning .capsule-stop[aria-pressed='true']",
             "phx-value-reasoning_effort"
           ) ==
             ["1"]

    assert text(
             dom,
             "#chat-llm-selection-provider-list .capsule-item[phx-value-provider_profile_id='']"
           ) ==
             "Auto (by rules)"

    # Placement: the picker lives in the composer card's control bar, inside
    # the ONE `#chat-form` (its items carry their own click bindings, so no
    # nested form or form owner is involved), and is gone from the page header
    # along with its old standalone form.
    assert Floki.find(dom, "#chat-form #chat-composer-controls #chat-llm-selection") != []
    assert Floki.find(dom, "#chat-header #chat-llm-selection") == []
    assert Floki.find(dom, "form#chat-llm-selection-form") == []
    assert Floki.find(dom, "select[name='model_id']") == []

    dom = page(provider_profiles: profiles, model_selections: selections, model_spec: spec)

    assert text(
             dom,
             "#chat-llm-selection-provider-list .capsule-item[phx-value-provider_profile_id='']"
           ) ==
             "Choose a provider profile"

    # A persisted id that no longer exists renders as a disabled, invalid row
    # that is never selected, and the drill row flags it too.
    stale = %{"provider_profile_id" => "removed-account"}

    dom = page(provider_profiles: profiles, model_selections: selections, model_spec: stale)

    assert attr(dom, "#chat-llm-selection-provider", "aria-invalid") == ["true"]

    assert attr(
             dom,
             "#chat-llm-selection-provider-list [role='option'][aria-invalid='true']",
             "phx-value-provider_profile_id"
           ) == ["removed-account"]

    assert Floki.find(
             dom,
             "#chat-llm-selection-provider-list .capsule-item-placeholder[disabled]"
           ) !=
             []

    assert attr(
             dom,
             "#chat-llm-selection-provider-list [role='option'][aria-selected='true']",
             "phx-value-provider_profile_id"
           ) == []

    assert text(dom, "#chat-llm-selection-provider .capsule-drill-value") ==
             "Unavailable profile: removed-account"
  end

  test "composer control bar pairs the picker with the send control inside one form" do
    profiles = [%{"id" => "work-account", "name" => "Work", "provider" => "openai"}]

    selections = [
      %{
        provider_profile_id: "work-account",
        model: "reasoned-model",
        reasoning_efforts: ["low", "high"],
        default_reasoning_effort: "low"
      }
    ]

    spec = %{"provider_profile_id" => "work-account", "model" => "reasoned-model"}
    dom = page(provider_profiles: profiles, model_selections: selections, model_spec: spec)

    # One form owns the whole composer; nothing is nested inside it.
    assert attr(dom, "#chat-form", "phx-submit") == ["send_message"]
    assert attr(dom, "#chat-form", "phx-change") == ["chat_input"]
    assert Floki.find(dom, "#chat-form #chat-form") == []
    assert Floki.find(dom, "#chat-form form") == []

    # Capsule on the left, send/stop on the right, both in the control bar row
    # that sits BELOW the textarea.
    assert Floki.find(dom, "#chat-composer-controls #chat-llm-selection") != []
    assert Floki.find(dom, "#chat-composer-controls button[type='submit']") != []
    assert Floki.find(dom, "#chat-composer-controls button[phx-click='stop']") != []

    assert Floki.find(dom, "#chat-form > textarea") != []
    assert Floki.find(dom, "#chat-form > textarea + #chat-composer-controls") != []

    # Provider rows carry their OWN click bindings, which LiveView dispatches
    # to `select_provider_profile` with the row's profile id; the textarea has
    # no own binding, so typing still hits the enclosing form's `chat_input`.
    assert attr(
             dom,
             "#chat-form #chat-llm-selection-provider-list [phx-click='select_provider_profile']",
             "phx-value-provider_profile_id"
           ) == ["", "work-account"]

    assert attr(dom, "#chat-form textarea", "phx-change") == []
  end

  test "loading, missing snapshots and invalid selections cannot enable sending" do
    for overrides <- [
          [model_select_loading: true, model_snapshot: nil],
          [model_snapshot: nil],
          [model_selection_error: :invalid_model_spec],
          [model_snapshot: nil, model_select_load_error: :remote_not_connected]
        ] do
      dom = page(overrides)
      assert Floki.find(dom, "#chat-form button[type='submit'][disabled]") != []
      # The draft remains editable while the model load/choice is repaired.
      assert Floki.find(dom, "#chat-form textarea[disabled]") == []
    end

    dom = page(model_snapshot: nil, model_select_load_error: :remote_not_connected)
    assert Floki.find(dom, "#chat-llm-selection.pointer-events-none.opacity-60") != []
    assert text(dom, "[role='alert']") =~ "Model selection is unavailable."
  end

  test "empty chat offers draft starters without starting tasks" do
    dom = page()
    assert text(dom, "h1") == "Assistant"
    assert Floki.find(dom, "#assistant-welcome") != []
    prompts = Floki.find(dom, "#chat-messages button[phx-click='draft_suggestion']")
    assert length(prompts) == 3
    assert Floki.find(dom, "#chat-messages button[phx-click='send_message']") == []
    assert Floki.find(dom, "#chat-messages #chat-form") == []
    assert attr(dom, "#chat-messages", "phx-hook") == ["AgentHistoryAutoScroll"]
  end

  test "composer preserves escaped drafts and delegates keyboard behavior to its hook" do
    dom = page(chat_draft: "Explain <this> & that")
    assert text(dom, "#assistant-message") == "Explain &lt;this&gt; &amp; that"
    assert attr(dom, "#chat-form", "phx-hook") == ["AssistantComposer"]
    assert attr(dom, "#chat-form", "phx-submit") == ["send_message"]
    assert attr(dom, "#assistant-message", "phx-keydown") == []
    assert attr(dom, "#assistant-message", "aria-label") == ["Message Genesis Assistant…"]
    assert attr(dom, "#assistant-send", "aria-label") == ["Send"]
    assert Floki.find(dom, "#assistant-message[disabled], #assistant-send[disabled]") == []
    assert Floki.find(dom, "#assistant-stop[disabled].hidden") != []
  end

  test "running chat keeps the draft editable and replaces send with stop" do
    dom = page(chat_status: :running)
    assert Floki.find(dom, "#assistant-message[disabled]") == []
    assert Floki.find(dom, "#assistant-send[disabled].hidden") != []
    assert attr(dom, "#assistant-stop", "aria-label") == ["Stop"]
    assert Floki.find(dom, "#assistant-stop[disabled], #assistant-stop.hidden") == []
    assert Floki.find(dom, "[role='status']") != []
  end

  test "restored conversation replaces the welcome surface" do
    dom = page(transcript: [%{id: "user-1", role: :user, text: "Explain the scheduler"}])
    assert text(dom, "#chat-messages") =~ "Explain the scheduler"
    assert Floki.find(dom, "#assistant-welcome") == []
    assert Floki.find(dom, "#assistant-message[disabled]") == []
  end

  test "source availability does not gate project conversations" do
    dom = page(source_available: false)
    assert Floki.find(dom, "#assistant-send[disabled]") == []
    assert Floki.find(dom, "button[phx-click='download_source']") == []
  end

  test "no workspace allows drafting and offers an in-place project action" do
    dom = page(workspace: nil)
    assert Floki.find(dom, "#assistant-message[disabled]") == []
    assert Floki.find(dom, "#assistant-send[disabled]") != []
    assert attr(dom, "#assistant-project-toggle", "phx-click") == ["toggle_workspace"]
    assert Floki.find(dom, "#assistant-shell a[href*='/projects']") == []
  end

  test "selected workspace appears in the header and unlocks sending" do
    dom = page(workspace: "/work/project-b")
    assert text(dom, "#assistant-project-toggle") == "project-b"
    assert Floki.find(dom, "#assistant-send[disabled]") == []
  end

  test "project selection stays inside the assistant" do
    dom = page(workspace_open: true, current_node_id: "workstation")
    assert Floki.find(dom, "#assistant-workspace-panel[role='dialog']") != []
    assert attr(dom, "#assistant-open-project-form", "phx-submit") == ["open_workspace"]

    assert length(
             Floki.find(dom, "#assistant-workspace-panel button[phx-click='open_workspace']")
           ) == 2

    assert Floki.find(dom, "#assistant-open-project-form input[name='path']") != []
  end
end
