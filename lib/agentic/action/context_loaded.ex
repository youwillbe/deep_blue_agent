defmodule Agentic.Action.ContextLoaded do
  use Jido.Action,
    name: "context_loaded"

  require Logger

  @impl true
  def run(params, ctx) do
    Logger.info("[Action.ContextLoaded] session=#{ctx.state.session_id}")

    {:ok, %{context: params.context}, [%Agentic.Directive.LoadTools{}]}
  end
end
