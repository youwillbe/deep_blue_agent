defmodule Agentic.Action.RunStarted do
  use Jido.Action,
    name: "run_started"

  require Logger

  alias Agentic.Directive.EmitEvent

  @impl true
  def run(_params, ctx) do
    sid = ctx.state.session_id
    run_id = UUIDv7.generate()
    pending = ctx.state.pending_inbox

    Logger.info("[Action.RunStarted] session=#{sid} run=#{run_id} pending=#{length(pending)}")

    # Consume pending inbox
    {inbox_directives, new_context} =
      if pending != [] do
        msgs = Enum.map(pending, fn %{content: c} -> %{role: :user, content: c} end)

        directives =
          Enum.flat_map(pending, fn %{key: key, content: c} ->
            [
              %EmitEvent{operation: "update", type: "inbox", key: key, value: %{status: "processed"}},
              %EmitEvent{operation: "insert", type: "context", key: "context:#{UUIDv7.generate()}",
                value: %{id: UUIDv7.generate(), name: "user", attrs: %{}, content: c,
                  timestamp: DateTime.utc_now() |> DateTime.to_iso8601()}}
            ]
          end)

        {directives, %{messages: ctx.state.context.messages ++ msgs}}
      else
        {[], ctx.state.context}
      end

    step_id = UUIDv7.generate()

    {:ok, step_start_signal} =
      Agentic.Signal.StepStart.new(%{step_id: step_id, run_id: run_id, step_number: 1, step_type: "call_llm"})

    {:ok, %{run_id: run_id, step_id: step_id, step_number: 1, status: :step_running,
            streaming_text: "", context: new_context, pending_inbox: []},
     inbox_directives ++ [
       %EmitEvent{operation: "insert", type: "run", key: "run:#{run_id}",
         value: %{id: "run_#{run_id}", status: "started"}},
       Jido.Agent.Directive.emit(step_start_signal)
     ]}
  end
end
