defmodule EvoDashWeb.HomeLive.Surface do
  @moduledoc "Presentation for the assistant's project and conversation surfaces."
  use EvoDashWeb, :html

  attr(:workspace, :any, default: nil)
  attr(:busy, :boolean, default: false)
  attr(:history_open, :boolean, default: false)
  attr(:workspace_open, :boolean, default: false)

  def header(assigns) do
    ~H"""
    <header class="assistant-header">
      <div class="assistant-heading">
        <span class="assistant-mark" aria-hidden="true"><.icon
          name="hero-command-line"
          class="size-5"
        /></span>
        <div class="min-w-0">
          <h1>{gettext("Assistant")}</h1>
          <button
            id="assistant-project-toggle"
            type="button"
            phx-click="toggle_workspace"
            disabled={@busy}
            class="assistant-project"
            aria-expanded={to_string(@workspace_open)}
            aria-controls="assistant-workspace-panel"
            title={@workspace || gettext("Choose project")}
          >
            <.icon name="hero-folder" class="size-3.5 shrink-0" />
            <span>{project_name(@workspace)}</span>
            <.icon name="hero-chevron-down" class="size-3 shrink-0" />
          </button>
        </div>
      </div>
      <div class="assistant-header-actions">
        <button
          id="assistant-history-toggle"
          type="button"
          phx-click="toggle_history"
          class={["assistant-icon-button", @history_open && "is-active"]}
          aria-label={gettext("Conversation history")}
          title={gettext("Conversation history")}
          aria-expanded={to_string(@history_open)}
          aria-controls="assistant-history"
        >
          <.icon name="hero-clock" class="size-5" />
        </button>
        <button
          id="assistant-new-chat"
          type="button"
          phx-click="new_chat"
          disabled={@busy}
          class="assistant-new-chat"
          title={gettext("New chat")}
        >
          <.icon name="hero-pencil-square" class="size-4" /><span class="assistant-new-chat-label">{gettext(
            "New chat"
          )}</span>
        </button>
      </div>
    </header>
    """
  end

  attr(:workspace, :any, default: nil)

  def welcome(assigns) do
    ~H"""
    <div id="assistant-welcome" class="assistant-welcome">
      <div class="assistant-welcome-mark" aria-hidden="true">
        <.icon name="hero-sparkles" class="size-6" />
      </div>
      <h2>{gettext("What shall we build next?")}</h2>
      <p>{gettext("Bring an idea. We will turn it into a plan and follow it through.")}</p>
      <div class="assistant-starters" aria-label={gettext("Conversation starters")}>
        <button type="button" phx-click="draft_suggestion" phx-value-kind="explore"><.icon
          name="hero-code-bracket"
          class="size-4"
        />{gettext("Explore a project")}</button>
        <button type="button" phx-click="draft_suggestion" phx-value-kind="plan"><.icon
          name="hero-pencil"
          class="size-4"
        />{gettext("Plan a change")}</button>
        <button type="button" phx-click="draft_suggestion" phx-value-kind="tasks"><.icon
          name="hero-queue-list"
          class="size-4"
        />{gettext("Follow my tasks")}</button>
      </div>
      <button
        :if={is_nil(@workspace)}
        id="assistant-workspace-required"
        class="assistant-inline-project"
        type="button"
        phx-click="toggle_workspace"
      >
        <.icon name="hero-folder-plus" class="size-4" />{gettext("Choose a project to get started")}
      </button>
    </div>
    """
  end

  attr(:projects, :list, default: [])
  attr(:form, :any, required: true)
  attr(:loading, :boolean, default: false)
  attr(:error, :any, default: nil)

  def workspace_panel(assigns) do
    ~H"""
    <section
      id="assistant-workspace-panel"
      class="assistant-panel assistant-workspace-panel"
      role="dialog"
      aria-labelledby="assistant-project-title"
      phx-click-away="close_workspace"
      phx-window-keydown={JS.push("dismiss_panels") |> JS.focus(to: "#assistant-project-toggle")}
      phx-key="Escape"
    >
      <.focus_wrap id="assistant-workspace-focus">
        <div class="assistant-panel-heading">
          <h2 id="assistant-project-title">{gettext("Choose project")}</h2>
          <button
            type="button"
            phx-click={JS.push("close_workspace") |> JS.focus(to: "#assistant-project-toggle")}
            class="assistant-icon-button"
            aria-label={gettext("Close")}
          ><.icon name="hero-x-mark" class="size-4" /></button>
        </div>
        <div :if={@projects != []} class="assistant-recents">
          <p class="assistant-section-label">{gettext("Recent projects")}</p>
          <button
            :for={project <- @projects}
            type="button"
            phx-click="open_workspace"
            phx-value-path={project.path}
            disabled={@loading}
            class="assistant-recent-project"
          >
            <.icon name="hero-folder" class="size-4 shrink-0" />
            <span><strong>{project.name}</strong><small>{project.path}</small></span>
            <.icon name="hero-arrow-up-right" class="size-4 shrink-0" />
          </button>
        </div>
        <.form
          for={@form}
          id="assistant-open-project-form"
          phx-submit="open_workspace"
          class="assistant-project-form"
        >
          <.input
            field={@form[:path]}
            id="assistant-project-path"
            label={gettext("Project directory")}
            placeholder="/home/user/project"
            autocomplete="off"
            phx-mounted={JS.focus(to: "#assistant-project-path")}
            disabled={@loading}
          />
          <p class="assistant-field-help">
            {gettext("Use an existing directory on the selected machine.")}
          </p>
          <p :if={@error} id="assistant-project-error" class="assistant-field-error" role="alert">
            {@error}
          </p>
          <button type="submit" disabled={@loading} class="assistant-primary-button"><.icon
            name="hero-folder-open"
            class="size-4"
          />{if @loading, do: gettext("Opening…"), else: gettext("Use this project")}</button>
        </.form>
      </.focus_wrap>
    </section>
    """
  end

  attr(:sessions, :list, default: [])

  def history_panel(assigns) do
    ~H"""
    <aside
      id="assistant-history"
      class="assistant-panel assistant-history"
      role="dialog"
      aria-labelledby="assistant-history-title"
      phx-click-away="close_history"
      phx-window-keydown={JS.push("dismiss_panels") |> JS.focus(to: "#assistant-history-toggle")}
      phx-key="Escape"
    >
      <.focus_wrap id="assistant-history-focus">
        <div class="assistant-panel-heading">
          <h2 id="assistant-history-title">{gettext("Conversation history")}</h2>
          <button
            type="button"
            phx-click={JS.push("close_history") |> JS.focus(to: "#assistant-history-toggle")}
            class="assistant-icon-button"
            aria-label={gettext("Close")}
          ><.icon name="hero-x-mark" class="size-4" /></button>
        </div>
        <p :if={@sessions == []} class="assistant-history-empty">
          {gettext("Your conversations will appear here.")}
        </p>
        <div class="assistant-session-list">
          <button
            :for={session <- @sessions}
            id={"assistant-session-" <> to_string(session.id)}
            type="button"
            phx-click="switch_chat"
            phx-value-id={session.id}
            class={["assistant-session", session.current? && "is-current"]}
            aria-current={if session.current?, do: "true", else: "false"}
          >
            <.icon name="hero-chat-bubble-left" class="size-4 shrink-0" />
            <span><strong>{if session.title == "", do: gettext("New chat"), else: session.title}</strong><small>{project_name(
              session.workspace
            )}</small></span>
            <.icon :if={session.current?} name="hero-check" class="size-4 shrink-0" />
          </button>
        </div>
      </.focus_wrap>
    </aside>
    """
  end

  def project_name(path) when is_binary(path) and path != "" do
    path
    |> String.replace("\\", "/")
    |> String.trim_trailing("/")
    |> String.split("/")
    |> List.last()
  end

  def project_name(_), do: gettext("Choose project")
end
