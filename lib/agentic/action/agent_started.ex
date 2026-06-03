defmodule Agentic.Action.AgentStarted do
  use Jido.Action,
    name: "agent_started"

  require Logger

  @impl true
  def run(_params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.AgentStarted] session=#{sid} model=#{ctx.state.model}")

    directives = [
      %Agentic.Directive.EmitEvent{
        operation: "insert",
        type: "agent",
        key: "agent:#{sid}",
        value: %{
          id: "agent_#{sid}",
          session_id: sid,
          model: ctx.state.model,
          status: "idle"
        }
      },
      %Agentic.Directive.LoadContext{}
    ]

    {:ok, %{}, directives}
  end
end
