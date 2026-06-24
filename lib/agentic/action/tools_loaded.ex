defmodule Agentic.Action.ToolsLoaded do
  use Jido.Action,
    name: "tools_loaded"

  require Logger

  @impl true
  def run(params, ctx) do
    Logger.info("[Action.ToolsLoaded] session=#{ctx.state.session_id}")

    # ctx.state.tools may be a list of modules (first run) or a name=>module map
    # (subsequent runs). Normalize to map for idempotent state updates.
    tools_map =
      case ctx.state.tools do
        tools when is_map(tools) ->
          tools

        tools when is_list(tools) ->
          Map.new(tools, fn mod -> {mod.name(), mod} end)
      end

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
