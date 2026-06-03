defmodule Agentic.Directive.CallTool do
  defstruct [:tool_call_id, :tool_name, :args, :run_id, :step_id, :step_number]
end

defimpl Jido.AgentServer.DirectiveExec, for: Agentic.Directive.CallTool do
  require Logger

  def exec(directive, _input_signal, state) do
    agent_id = state.id
    task_sup = Jido.task_supervisor_name(state.jido)
    tool_module = Map.get(state.agent.state.tools, directive.tool_name)

    # Prepare and validate args
    args =
      if tool_module do
        Jido.Action.Tool.convert_params_using_schema(directive.args, tool_module.schema())
      else
        directive.args
      end

    Logger.info("[Directive.CallTool] tool=#{directive.tool_name} call_id=#{directive.tool_call_id}")

    Task.Supervisor.start_child(task_sup, fn ->
      {:ok, signal} =
        Agentic.Signal.ToolCallArgsReady.new(%{
          tool_call_id: directive.tool_call_id,
          tool_name: directive.tool_name,
          args: args,
          run_id: directive.run_id,
          step_id: directive.step_id,
          step_number: directive.step_number
        })

      case DeepBlue.Jido.whereis(agent_id) do
        pid when is_pid(pid) -> Jido.AgentServer.cast(pid, signal)
        nil -> Logger.error("[Directive.CallTool] agent not found: #{agent_id}")
      end
    end)

    {:async, nil, state}
  end
end
