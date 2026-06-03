defmodule Agentic.Action.ToolResultReceived do
  use Jido.Action,
    name: "tool_result_received"

  require Logger

  alias Agentic.Directive.EmitEvent

  @impl true
  def run(params, ctx) do
    sid = ctx.state.session_id
    has_error = Map.has_key?(params, :error) && params.error != nil

    Logger.info("[Action.ToolResultReceived] session=#{sid} tool=#{params.tool_name} #{if has_error, do: "error", else: "ok"}")

    status = (has_error && "failed") || "completed"

    sc_params =
      %{step_id: params.step_id, run_id: params.run_id,
        step_number: params.step_number, finish_reason: "tool_executed",
        tool_call_id: params.tool_call_id, result: params[:result]}
      |> then(&if(params[:error], do: Map.put(&1, :error, params.error), else: &1))

    {:ok, step_complete} = Agentic.Signal.StepComplete.new(sc_params)

    {:ok, %{},
     [
       %EmitEvent{operation: "update", type: "tool_call", key: "tool_call:#{params.tool_call_id}",
         value: %{tool_call_id: params.tool_call_id, run_id: params.run_id, tool_name: params.tool_name,
           status: status, result: params[:result], error: params[:error]}},
       Jido.Agent.Directive.emit(step_complete)
     ]}
  end
end
