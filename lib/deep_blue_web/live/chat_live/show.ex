defmodule DeepBlueWeb.ChatLive.Show do
  use DeepBlueWeb, :live_view

  alias DeepBlue.Chat
  import DeepBlueWeb.ChatLive.Components
  alias DurableStreams.LiveView, as: DSLive

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> DSLive.init()
      |> assign(:form, init_form())
      |> assign(:timeline, [])
      |> stream(:sessions, Chat.list_chat_sessions())
      |> stream(:messages, [])

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Chat.get_session(id) do
      {:ok, session} ->
        Chat.ensure_session(session)

        socket =
          socket
          |> assign(:session, session)
          |> assign(:timeline, [])
          |> stream(:sessions, Chat.list_chat_sessions(), reset: true)
          |> stream(:messages, [], reset: true)

        if connected?(socket) do
          socket = DSLive.listen(socket, "session-#{id}")
          {:noreply, socket}
        else
          {:noreply, socket}
        end

      {:error, :not_found} ->
        {:noreply, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("send_msg", %{"input" => input}, socket) do
    input = String.trim(input)

    if input == "" do
      {:noreply, socket}
    else
      pid = DeepBlue.Jido.whereis(socket.assigns.session.id)
      Agentic.Agent.chat(pid, input)

      {:noreply, assign(socket, :form, init_form())}
    end
  end

  def handle_event("new_session", _params, socket) do
    case Chat.create_session(%{title: "new session"}) do
      {:ok, session} ->
        {:noreply, push_navigate(socket, to: ~p"/sessions/#{session.id}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "创建失败")}
    end
  end

  def handle_event("delete_session", _params, socket) do
    session = socket.assigns.session

    with {:ok, _deleted} <- Chat.delete_session(session) do
      first =
        Chat.list_chat_sessions()
        |> Enum.reject(&(&1.id == session.id))
        |> List.first()

      target = if first, do: ~p"/sessions/#{first.id}", else: ~p"/"
      {:noreply, push_navigate(socket, to: target)}
    else
      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("change_msg", params, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  @impl true
  def handle_info(msg, socket) do
    if DSLive.stream_message?(msg) do
      case DSLive.handle_message(socket, msg) do
        {:data, messages, socket} ->
          {:noreply, process_messages(socket, messages)}

        {:status, _status, socket} ->
          {:noreply, socket}

        {:complete, socket} ->
          {:noreply, socket}

        {:error, _reason, socket} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.chat flash={@flash} show_sidebar={true}>
      <:sidebar>
        <.sidebar sessions={@streams.sessions} current={@session.id} />
      </:sidebar>

      <div class="flex flex-col h-full">
        <div class="shrink-0 px-4 py-3 border-b border-base-300 flex items-center justify-between">
          <h2 class="text-sm font-medium truncate">{@session.title || "新对话"}</h2>
          <button phx-click="delete_session" class="btn btn-ghost btn-xs text-error">
            <.icon name="hero-trash" class="size-4" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto px-4 py-4 space-y-4">
          <.timeline_section :for={section <- @timeline} section={section} />
          <div
            :if={Enum.empty?(@timeline)}
            class="flex items-center justify-center h-full text-base-content/40 text-sm"
          >
            暂无对话
          </div>
        </div>

        <div class="shrink-0 border-t border-base-300 p-4">
          <.form for={@form} phx-submit="send_msg" phx-change="change_msg">
            <.input field={@form[:input]} placeholder="输入消息..." autocomplete="off" />
          </.form>
        </div>
      </div>

      <:right_panel>
        <div class="flex flex-col h-full">
          <div class="shrink-0 px-3 py-2 border-b border-base-300 text-xs text-base-content/40 font-mono uppercase">
            Events
          </div>
          <div id="events-scroll" class="flex-1 overflow-y-auto p-2 space-y-1">
            <div id="events" phx-update="stream" class="space-y-1">
              <.event_item :for={{dom_id, msg} <- @streams.messages} id={dom_id} event={msg} />
            </div>
          </div>
        </div>
      </:right_panel>
    </Layouts.chat>
    """
  end

  # -- timeline section --

  attr :section, :map, required: true

  defp timeline_section(assigns) do
    ~H"""
    <div :if={@section.kind == :user_message} class="flex justify-end">
      <div class="max-w-[80%] bg-blue-50 border border-blue-200 rounded-lg px-4 py-2">
        <p class="text-sm whitespace-pre-wrap">{@section.text}</p>
      </div>
    </div>
    <div :if={@section.kind == :agent_response} class="flex justify-start">
      <div class="max-w-[80%] bg-white border border-base-200 rounded-lg px-4 py-2">
        <p :if={@section.status == :streaming && @section.content == ""} class="text-sm text-base-content/40 italic">
          思考中...
        </p>
        <p :if={@section.content != ""} class="text-sm whitespace-pre-wrap">{@section.content}</p>
        <span :if={@section.status == :streaming && @section.content != ""} class="inline-block w-2 h-4 bg-base-content/60 animate-pulse ml-0.5 align-text-bottom" />
      </div>
    </div>
    <div :if={@section.kind == :tool_call} class="flex justify-start">
      <div class="max-w-[80%] bg-cyan-50 border border-cyan-200 rounded-lg px-4 py-2">
        <div class="flex items-center gap-2 mb-1">
          <span class="text-xs px-1.5 py-0.5 rounded border font-mono text-cyan-600 bg-cyan-50 border-cyan-200">
            {@section.name}
          </span>
          <span class={[
            "text-xs px-1.5 py-0.5 rounded border font-mono",
            (@section.status in [:running, "args_complete", "executing"] && "text-amber-600 bg-amber-50 border-amber-200") ||
              (@section.status in [:done, "completed"] && "text-green-600 bg-green-50 border-green-200") ||
              "text-red-600 bg-red-50 border-red-200"
          ]}>
            {@section.status}
          </span>
        </div>
        <div :if={Map.has_key?(@section, :args)} class="mt-1">
          <span class="text-xs text-base-content/40">Args:</span>
          <pre class="text-xs p-2 bg-base-200 rounded overflow-x-auto"><code>{inspect(@section.args, pretty: true, width: 40)}</code></pre>
        </div>
        <div :if={Map.has_key?(@section, :detail)} class="mt-1">
          <span class="text-xs text-base-content/40">Result:</span>
          <pre class="text-xs p-2 bg-base-200 rounded overflow-x-auto"><code>{inspect(@section.detail, pretty: true, width: 40)}</code></pre>
        </div>
      </div>
    </div>
    """
  end

  # -- event item (right panel) --

  attr :id, :string, required: true
  attr :event, :map, required: true

  defp event_item(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-1 p-2 border border-base-200 bg-white text-xs">
      <div class="flex items-center gap-2">
        <span class={["shrink-0 px-1.5 py-0.5 rounded border font-mono", type_badge_color(@event.type)]}>
          {@event.type}
        </span>
        <span class="text-base-content/40 font-mono uppercase">{@event.operation}</span>
      </div>
      <pre class="text-xs whitespace-pre-wrap break-all pt-1"><%= event_summary(@event) %></pre>
    </div>
    """
  end

  defp event_summary(%{type: "inbox", payload: %{"from" => from, "payload" => p, "status" => s, "mode" => m}}),
    do: "[#{from}] #{p} (#{s}/#{m})"
  defp event_summary(%{type: "inbox", payload: %{"status" => s}}),
    do: "-> #{s}"
  defp event_summary(%{type: "inbox", payload: %{"from" => from, "payload" => p}}),
    do: "[#{from}] #{p}"
  defp event_summary(%{type: "run", payload: %{"status" => s}}), do: s
  defp event_summary(%{type: "step", payload: %{"step_number" => n, "status" => s}}), do: "#{n} #{s}"
  defp event_summary(%{type: "text", payload: %{"status" => s}}), do: s
  defp event_summary(%{type: "text_delta", payload: %{"delta" => d}}), do: d
  defp event_summary(%{type: "session"}), do: "created"
  defp event_summary(%{type: "agent"}), do: "started"
  defp event_summary(%{type: "tool_call", payload: %{"status" => "started", "args" => a}}) when is_map(a), do: Jason.encode!(a)
  defp event_summary(%{type: "tool_call", payload: %{"status" => s, "result" => r}}) when s in ["completed", "failed"] and is_map(r), do: Jason.encode!(r)
  defp event_summary(%{type: "tool_call", payload: %{"status" => "started", "args" => a}}), do: to_string(a)
  defp event_summary(%{type: "tool_call", payload: %{"status" => s, "result" => r}}) when s in ["completed", "failed"], do: to_string(r)
  defp event_summary(%{type: "tool_call", payload: %{"tool_name" => n, "status" => s}}), do: "#{n} #{s}"
  defp event_summary(%{type: "context", payload: %{"name" => n, "content" => c}}), do: "[#{n}] #{c}"
  defp event_summary(%{type: "llm_call", payload: %{"status" => s}}), do: s
  defp event_summary(%{type: "error", payload: %{"error_code" => c}}), do: c
  defp event_summary(_), do: ""

  defp type_badge_color("inbox"), do: "text-blue-600 bg-blue-50 border-blue-200"
  defp type_badge_color("run"), do: "text-gray-600 bg-gray-100 border-gray-300"
  defp type_badge_color("step"), do: "text-gray-500 bg-gray-50 border-gray-200"
  defp type_badge_color("session"), do: "text-green-600 bg-green-50 border-green-200"
  defp type_badge_color("agent"), do: "text-amber-600 bg-amber-50 border-amber-200"
  defp type_badge_color("text"), do: "text-indigo-600 bg-indigo-50 border-indigo-200"
  defp type_badge_color("text_delta"), do: "text-indigo-400 bg-indigo-50/50 border-indigo-100"
  defp type_badge_color("reasoning"), do: "text-purple-600 bg-purple-50 border-purple-200"
  defp type_badge_color("tool_call"), do: "text-cyan-600 bg-cyan-50 border-cyan-200"
  defp type_badge_color("context"), do: "text-teal-600 bg-teal-50 border-teal-200"
  defp type_badge_color("llm_call"), do: "text-purple-600 bg-purple-50 border-purple-200"
  defp type_badge_color("error"), do: "text-red-600 bg-red-50 border-red-200"
  defp type_badge_color(_), do: "text-gray-500 bg-gray-50 border-gray-200"

  # -- message processing --

  defp process_messages(socket, messages) do
    decoded = Enum.map(messages, fn msg ->
      d = JSON.decode!(msg.data)
      {msg.offset, d["type"], d["value"], d["headers"]["operation"]}
    end)

    socket =
      Enum.reduce(decoded, socket, fn {offset, type, value, op}, socket ->
        stream_insert(socket, :messages, %{
          id: offset, type: type, operation: op, payload: stringify(value)
        })
      end)

    timeline = Enum.reduce(decoded, socket.assigns.timeline, fn {_offset, type, value, op}, tl ->
      update_timeline(tl, type, op, value)
    end)

    assign(socket, :timeline, timeline)
  end

  defp update_timeline(tl, "inbox", "insert", value) do
    if value["from"] == "user" do
      tl ++ [%{kind: :user_message, text: value["payload"]}]
    else
      tl
    end
  end

  defp update_timeline(tl, "text", "insert", _value) do
    tl ++ [%{kind: :agent_response, status: :streaming, content: ""}]
  end

  defp update_timeline(tl, "text_delta", "insert", value) do
    update_last_agent(tl, fn s -> %{s | content: s.content <> value["delta"]} end)
  end

  defp update_timeline(tl, "text", "update", _value) do
    update_last_agent(tl, fn s -> %{s | status: :done, content: String.trim_trailing(s.content, "\n")} end)
  end

  defp update_timeline(tl, "tool_call", op, value) do
    case {op, value["status"]} do
      {"insert", _} ->
        tl ++ [%{kind: :tool_call, call_id: value["tool_call_id"], name: value["tool_name"], status: :running, args: value["args"]}]
      {"update", "completed"} ->
        update_tool(tl, value["tool_call_id"], :done, value["result"])
      {"update", "failed"} ->
        update_tool(tl, value["tool_call_id"], :error, value["error"])
      {"update", status} ->
        update_tool(tl, value["tool_call_id"], status)
      _ -> tl
    end
  end

  defp update_timeline(tl, _type, _op, _value), do: tl

  defp update_last_agent(tl, func) do
    case Enum.find_index(Enum.reverse(tl), &(&1.kind == :agent_response)) do
      nil -> tl
      rev_idx -> List.update_at(tl, length(tl) - 1 - rev_idx, func)
    end
  end

  defp update_tool(tl, call_id, status, detail \\ nil) do
    Enum.map(tl, fn
      %{kind: :tool_call, call_id: ^call_id} = s ->
        s = %{s | status: status}
        if detail, do: Map.put(s, :detail, detail), else: s
      s -> s
    end)
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp init_form do
    to_form(%{"input" => ""})
  end
end
