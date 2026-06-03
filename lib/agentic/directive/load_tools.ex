defmodule Agentic.Directive.LoadTools do
  defstruct []
end

defimpl Jido.AgentServer.DirectiveExec, for: Agentic.Directive.LoadTools do
  require Logger

  def exec(_directive, _input_signal, state) do
    agent_id = state.id
    tools = state.agent.state.tools
    task_sup = Jido.task_supervisor_name(state.jido)

    Logger.info("[Directive.LoadTools] session=#{agent_id}")

    Task.Supervisor.start_child(task_sup, fn ->
      modules = if is_map(tools), do: Map.values(tools), else: tools
      llm_tools = Agentic.Tool.Adapter.from_actions(modules)

      {:ok, signal} = Agentic.Signal.ToolsLoaded.new(%{llm_tools: llm_tools})

      case DeepBlue.Jido.whereis(agent_id) do
        pid when is_pid(pid) -> Jido.AgentServer.cast(pid, signal)
        nil -> Logger.error("[Directive.LoadTools] agent not found: #{agent_id}")
      end
    end)

    {:async, nil, state}
  end
end
