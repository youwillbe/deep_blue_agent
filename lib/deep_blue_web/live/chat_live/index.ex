defmodule DeepBlueWeb.ChatLive.Index do
  use DeepBlueWeb, :live_view

  alias DeepBlue.Chat

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :form, init_form())}
  end

  @impl true
  def handle_event("send_msg", %{"input" => input}, socket) do
    input = String.trim(input)

    if input == "" do
      {:noreply, socket}
    else
      case Chat.create_session(%{title: input}) do
        {:ok, session} ->
          pid = DeepBlue.Jido.whereis(session.id)
          Agentic.Agent.chat(pid, input)

          socket =
            socket
            |> push_navigate(to: ~p"/sessions/#{session.id}")

          {:noreply, socket}

        {:error, reason} ->
          require Logger
          Logger.error("[ChatLive.Index] create_session failed: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "创建会话失败")}
      end
    end
  end

  def handle_event("change_msg", params, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col items-center justify-center min-h-[60vh]">
        <h1 class="text-2xl font-bold mb-8">Deep Blue</h1>
        <.form for={@form} phx-submit="send_msg" class="w-full max-w-xl">
          <.input field={@form[:input]} placeholder="开始新对话..." autocomplete="off" />
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp init_form do
    to_form(%{"input" => ""})
  end
end
