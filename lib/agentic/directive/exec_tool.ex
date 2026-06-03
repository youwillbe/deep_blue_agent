defmodule Agentic.Directive.ExecTool do
  defstruct [:tool_call_id, :tool_name, :args, :run_id, :step_id, :step_number]
end

defimpl Jido.AgentServer.DirectiveExec, for: Agentic.Directive.ExecTool do
  require Logger

  def exec(directive, _input_signal, state) do
    agent_id = state.id
    task_sup = Jido.task_supervisor_name(state.jido)
    tool_module = Map.get(state.agent.state.tools, directive.tool_name)

    Logger.info("[Directive.ExecTool] tool=#{directive.tool_name} call_id=#{directive.tool_call_id}")

    Task.Supervisor.start_child(task_sup, fn ->
      # Send executing status
      {:ok, executing_signal} =
        Agentic.Signal.ToolCallExecuting.new(%{
          tool_call_id: directive.tool_call_id,
          tool_name: directive.tool_name,
          run_id: directive.run_id,
          step_id: directive.step_id,
          step_number: directive.step_number
        })

      cast_to_agent(agent_id, executing_signal)

      # Execute tool
      result =
        if tool_module do
          case Jido.Exec.run(tool_module, directive.args) do
            {:ok, output} -> {:ok, output}
            {:error, error} -> {:error, error}
          end
        else
          {:error, "tool not found: #{directive.tool_name}"}
        end

      # Send result
      {:ok, signal} =
        case result do
          {:ok, output} ->
            Agentic.Signal.ToolResult.new(%{
              tool_call_id: directive.tool_call_id,
              tool_name: directive.tool_name,
              result: output,
              run_id: directive.run_id,
              step_id: directive.step_id,
              step_number: directive.step_number
            })

          {:error, error} ->
            Agentic.Signal.ToolResult.new(%{
              tool_call_id: directive.tool_call_id,
              tool_name: directive.tool_name,
              error: inspect(error),
              run_id: directive.run_id,
              step_id: directive.step_id,
              step_number: directive.step_number
            })
        end

      cast_to_agent(agent_id, signal)
    end)

    {:async, nil, state}
  end

  defp cast_to_agent(agent_id, signal) do
    case DeepBlue.Jido.whereis(agent_id) do
      pid when is_pid(pid) -> Jido.AgentServer.cast(pid, signal)
      nil -> Logger.error("[Directive.ExecTool] agent not found: #{agent_id}")
    end
  end
end
