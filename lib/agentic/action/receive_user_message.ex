defmodule Agentic.Action.ReceiveUserMessage do
  use Jido.Action,
    name: "receive_user_message"

  require Logger

  alias Agentic.Directive.EmitEvent

  @impl true
  def run(params, ctx) do
    id = UUIDv7.generate()
    agent_ready = ctx.state.status == :idle

    Logger.info("[Action.ReceiveUserMessage] ready=#{agent_ready} content=#{inspect(params[:content])}")

    msgs = if is_map(ctx.state.context), do: ctx.state.context.messages, else: []
    new_context = %{messages: msgs ++ [%{role: :user, content: params.content}]}

    inbox_event = %EmitEvent{
      operation: "insert",
      type: "inbox",
      key: "inbox:#{id}",
      value: %{
        id: id,
        from: "user",
        payload: params.content,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        mode: (agent_ready && "immediate") || "queued",
        status: (agent_ready && "processed") || "pending"
      }
    }

    if agent_ready do
      {:ok, run_start_signal} = Agentic.Signal.RunStart.new(%{})

      {:ok, %{context: new_context},
       [
         inbox_event,
         %EmitEvent{operation: "insert", type: "context", key: "context:#{UUIDv7.generate()}",
           value: %{id: UUIDv7.generate(), name: "user", attrs: %{}, content: params.content,
             timestamp: DateTime.utc_now() |> DateTime.to_iso8601()}},
         Jido.Agent.Directive.emit(run_start_signal)
       ]}
    else
      {:ok, %{pending_inbox: ctx.state.pending_inbox ++ [%{key: "inbox:#{id}", content: params.content}]},
       [inbox_event]}
    end
  end
end
