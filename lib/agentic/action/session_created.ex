defmodule Agentic.Action.SessionCreated do
  use Jido.Action,
    name: "session_created"

  require Logger

  @impl true
  def run(_params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.SessionCreated] session=#{sid}")

    {:ok, agent_started_signal} = Agentic.Signal.AgentStarted.new(%{})

    directives = [
      %Agentic.Directive.EmitEvent{
        operation: "insert",
        type: "session",
        key: "session:#{sid}",
        value: %{id: "session_#{sid}", status: "created"}
      },
      Jido.Agent.Directive.emit(agent_started_signal)
    ]

    {:ok, %{}, directives}
  end
end
