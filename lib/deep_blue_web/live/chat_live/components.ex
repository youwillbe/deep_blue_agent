defmodule DeepBlueWeb.ChatLive.Components do
  use DeepBlueWeb, :html

  attr :sessions, :list, required: true
  attr :current, :string, default: nil

  def sidebar(assigns) do
    ~H"""
    <div class="p-3 border-b border-base-300">
      <button phx-click="new_session" class="btn btn-sm btn-primary w-full">
        <.icon name="hero-plus" class="size-4" /> 新对话
      </button>
    </div>
    <div id="sessions-list" phx-update="stream" class="flex-1 overflow-y-auto p-2 space-y-1">
      <div :for={{dom_id, session} <- @sessions} id={dom_id}>
        <.link
          navigate={~p"/sessions/#{session.id}"}
          class={[
            "flex items-center gap-2 px-3 py-2 rounded-lg text-sm truncate transition-colors",
            @current != nil and session.id == @current && "bg-primary text-primary-content",
            @current == nil or session.id != @current && "hover:bg-base-300"
          ]}
        >
          <.icon name="hero-chat-bubble-left" class="size-4 shrink-0" />
          <span class="truncate">{session.title || "新对话"}</span>
        </.link>
      </div>
    </div>
    """
  end
end
