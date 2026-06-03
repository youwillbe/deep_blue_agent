defmodule Agentic.Action.RunCompleted do
  use Jido.Action,
    name: "run_completed"

  require Logger

  alias Agentic.Directive.EmitEvent

  @impl true
  def run(params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.RunCompleted] session=#{sid} run=#{params.run_id}")

    directives = [
      %EmitEvent{operation: "update", type: "run", key: "run:#{params.run_id}",
        value: %{id: "run_#{params.run_id}", status: "completed", finish_reason: params.finish_reason}}
    ]

    directives =
      if ctx.state.pending_inbox != [] do
        {:ok, signal} = Agentic.Signal.RunStart.new(%{})
        directives ++ [Jido.Agent.Directive.emit(signal)]
      else
        directives
      end

    {:ok, %{status: :idle, streaming_text: ""}, directives}
  end
end
