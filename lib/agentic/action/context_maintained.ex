defmodule Agentic.Action.ContextMaintained do
  use Jido.Action,
    name: "context_maintained"

  require Logger

  alias Agentic.Directive.EmitEvent

  @impl true
  def run(params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.ContextMaintained] session=#{sid} type=#{params.entry_type} reason=#{params.finish_reason}")

    # 1. State context update (event already emitted by TextReceived)
    new_context =
      case params.entry_type do
        "assistant" ->
          content = params[:content] || ""
          if content != "" do
            %{messages: ctx.state.context.messages ++ [%{role: :assistant, content: content}]}
          else
            ctx.state.context
          end

        "tool_result" ->
          result_text = Jason.encode!(params.result || %{})
          %{messages: ctx.state.context.messages ++ [%{role: :tool_result, call_id: params.tool_call_id, result: result_text}]}
      end

    # 2. Close step (container)
    step_update = %EmitEvent{operation: "update", type: "step", key: "step:#{params.step_id}",
      value: %{id: "step_#{params.step_id}", run_id: params.run_id,
        step_number: params.step_number, status: "completed", finish_reason: params.finish_reason}}

    # 3. Next phase routing
    {state, next_signals} =
      case params.finish_reason do
        "stop" ->
          {:ok, rc} = Agentic.Signal.RunComplete.new(%{run_id: ctx.state.run_id, finish_reason: "stop"})
          {%{status: :idle, streaming_text: ""}, [Jido.Agent.Directive.emit(rc)]}

        "tool_calls" ->
          tcs = ctx.state.tool_calls
          {last_sn, signals} =
            Enum.reduce(tcs, {ctx.state.step_number, []}, fn tc, {sn, acc} ->
              new_sn = sn + 1
              {:ok, ss} =
                Agentic.Signal.StepStart.new(%{step_id: UUIDv7.generate(), run_id: tc.run_id,
                  step_number: new_sn, step_type: "call_tool",
                  tool_call_id: tc.tool_call_id, tool_name: tc.tool_name, args: tc.args})
              {new_sn, acc ++ [Jido.Agent.Directive.emit(ss)]}
            end)

          {%{tool_calls: [], step_number: last_sn, status: :calling_tools}, signals}

        "tool_executed" ->
          remaining = ctx.state.tool_calls |> Enum.reject(&(&1.tool_call_id == params.tool_call_id))

          if remaining == [] do
            new_step_id = UUIDv7.generate()
            new_step_number = ctx.state.step_number + 1

            {:ok, ss} =
              Agentic.Signal.StepStart.new(%{step_id: new_step_id, run_id: ctx.state.run_id,
                step_number: new_step_number, step_type: "call_llm"})

            {%{tool_calls: [], step_id: new_step_id, step_number: new_step_number, status: :step_running},
             [Jido.Agent.Directive.emit(ss)]}
          else
            {%{tool_calls: remaining}, []}
          end

        _ ->
          {%{}, []}
      end

    {:ok, Map.merge(%{context: new_context}, state),
     [step_update | next_signals]}
  end
end
