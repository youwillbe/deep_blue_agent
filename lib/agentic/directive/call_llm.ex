defmodule Agentic.Directive.CallLLM do
  defstruct [:model, :context, :tools]
end

defimpl Jido.AgentServer.DirectiveExec, for: Agentic.Directive.CallLLM do
  require Logger

  def exec(directive, _input_signal, state) do
    model = directive.model
    tools = directive.tools
    agent_id = state.id
    run_id = state.agent.state.run_id
    step_id = state.agent.state.step_id
    step_number = state.agent.state.step_number

    messages = if is_map(directive.context), do: directive.context.messages, else: directive.context
    llm_context = build_llm_context(messages)

    opts = [receive_timeout: 60_000]
    opts = if tools != nil and tools != [], do: Keyword.put(opts, :tools, tools), else: opts

    Logger.info("[Directive.CallLLM] model=#{model} session=#{agent_id}")

    task_sup = Jido.task_supervisor_name(state.jido)

    Task.Supervisor.start_child(task_sup, fn ->
      case ReqLLM.stream_text(model, llm_context, opts) do
        {:ok, stream_res} ->
          process_stream(agent_id, run_id, step_id, step_number, stream_res)

        {:error, reason} ->
          send_error(agent_id, run_id, step_id, step_number, inspect(reason))
      end
    end)

    {:async, nil, state}
  end

  defp process_stream(agent_id, run_id, step_id, step_number, stream_res) do
    text_id = "text_#{step_id}"

    {:ok, tracker} = Agent.start_link(fn -> false end)

    case ReqLLM.StreamResponse.process_stream(stream_res,
           on_result: fn delta ->
             if String.trim(delta) != "" do
               if !Agent.get(tracker, & &1) do
                 send_text(agent_id, run_id, step_id, step_number, false)
                 Agent.update(tracker, fn _ -> true end)
               end

               send_delta(agent_id, run_id, text_id, delta)
             end
           end,
           on_thinking: fn _delta -> :ok end
         ) do
      {:ok, response} ->
        had_text = Agent.get(tracker, & &1)
        Agent.stop(tracker)

        case response.finish_reason do
          :stop ->
            send_text(agent_id, run_id, step_id, step_number, true, "stop")

          :tool_calls ->
            if had_text do
              send_text(agent_id, run_id, step_id, step_number, true, "tool_calls")
            else
              send_step_complete(agent_id, run_id, step_id, step_number, "tool_calls")
            end

            Enum.each(response.message.tool_calls || [], fn tc ->
              {:ok, signal} =
                Agentic.Signal.ToolCall.new(%{
                  tool_call_id: tc.id,
                  tool_name: tc.function.name,
                  args: Jason.decode!(tc.function.arguments),
                  run_id: run_id,
                  step_id: step_id,
                  step_number: step_number
                })

              cast_to_agent(agent_id, signal)
            end)

          reason ->
            send_error(agent_id, run_id, step_id, step_number, "finish_reason: #{reason}")
        end

      {:error, error} ->
        Agent.stop(tracker)
        send_error(agent_id, run_id, step_id, step_number, inspect(error))
    end
  end

  defp send_text(agent_id, run_id, step_id, step_number, done, finish_reason \\ nil) do
    params = %{run_id: run_id, step_id: step_id, step_number: step_number, done: done}
    params = if finish_reason, do: Map.put(params, :finish_reason, finish_reason), else: params

    {:ok, signal} = Agentic.Signal.Text.new(params)
    cast_to_agent(agent_id, signal)
  end

  defp send_delta(agent_id, run_id, text_id, delta) do
    {:ok, signal} =
      Agentic.Signal.TextDelta.new(%{delta: delta, text_id: text_id, run_id: run_id})

    cast_to_agent(agent_id, signal)
  end

  defp send_error(agent_id, run_id, step_id, step_number, reason) do
    {:ok, signal} =
      Agentic.Signal.Text.new(%{error: reason, run_id: run_id, step_id: step_id, step_number: step_number})

    cast_to_agent(agent_id, signal)
  end

  defp send_step_complete(agent_id, run_id, step_id, step_number, finish_reason) do
    {:ok, signal} =
      Agentic.Signal.StepComplete.new(%{
        step_id: step_id, run_id: run_id,
        step_number: step_number, finish_reason: finish_reason
      })

    cast_to_agent(agent_id, signal)
  end

  defp build_llm_context(list) when is_list(list) do
    list
    |> Enum.map(fn
      %{role: :system, content: c} -> ReqLLM.Context.system(c)
      %{role: :user, content: c} -> ReqLLM.Context.user(c)
      %{role: :assistant, content: c} -> ReqLLM.Context.assistant(c)
      %{role: :tool_call, name: name, args: args} -> ReqLLM.Context.assistant("", tool_calls: [{name, args}])
      %{role: :tool_result, call_id: id, result: result} -> ReqLLM.Context.tool_result(id, result)
    end)
    |> ReqLLM.Context.new()
  end

  defp cast_to_agent(agent_id, signal) do
    case DeepBlue.Jido.whereis(agent_id) do
      pid when is_pid(pid) -> Jido.AgentServer.cast(pid, signal)
      nil -> Logger.error("[Directive.CallLLM] agent not found: #{agent_id}")
    end
  end
end
