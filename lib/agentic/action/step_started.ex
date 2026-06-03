defmodule Agentic.Action.StepStarted do
  use Jido.Action,
    name: "step_started"

  require Logger

  alias Agentic.Directive.{CallLLM, CallTool, EmitEvent}

  @impl true
  def run(params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.StepStarted] session=#{sid} step=#{params.step_number} type=#{params.step_type}")

    step_insert = %EmitEvent{operation: "insert", type: "step", key: "step:#{params.step_id}",
      value: %{id: "step_#{params.step_id}", run_id: params.run_id,
        step_number: params.step_number, status: "started"}}

    case params.step_type do
      "call_llm" ->
        llm_call = %EmitEvent{operation: "insert", type: "llm_call", key: "llm_call:#{params.step_id}",
          value: %{id: "llm_call_#{params.step_id}", status: "started"}}

        {:ok, %{step_id: params.step_id, step_number: params.step_number, status: :step_running},
         [step_insert, llm_call, %CallLLM{model: ctx.state.model, context: ctx.state.context, tools: ctx.state.llm_tools}]}

      "call_tool" ->
        {:ok, %{step_id: params.step_id, step_number: params.step_number, status: :calling_tools},
         [step_insert,
          %EmitEvent{operation: "insert", type: "tool_call", key: "tool_call:#{params.tool_call_id}",
            value: %{tool_call_id: params.tool_call_id, run_id: params.run_id,
              tool_name: params.tool_name, status: "started", args: params.args}},
          %CallTool{tool_call_id: params.tool_call_id, tool_name: params.tool_name,
            args: params.args, run_id: params.run_id, step_id: params.step_id, step_number: params.step_number}]}
    end
  end
end
