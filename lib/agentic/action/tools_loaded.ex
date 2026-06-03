defmodule Agentic.Action.ToolsLoaded do
  use Jido.Action,
    name: "tools_loaded"

  require Logger

  @impl true
  def run(params, ctx) do
    Logger.info("[Action.ToolsLoaded] session=#{ctx.state.session_id}")

    tools_map = Map.new(ctx.state.tools, fn mod -> {mod.name(), mod} end)

    directives =
      if ctx.state.pending_inbox != [] do
        {:ok, signal} = Agentic.Signal.RunStart.new(%{})
        [Jido.Agent.Directive.emit(signal)]
      else
        []
      end

    {:ok, %{llm_tools: params.llm_tools, tools: tools_map, status: :idle, tool_calls: []}, directives}
  end
end
