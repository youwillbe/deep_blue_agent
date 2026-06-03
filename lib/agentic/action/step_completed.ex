defmodule Agentic.Action.StepCompleted do
  use Jido.Action,
    name: "step_completed"

  require Logger

  @impl true
  def run(params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.StepCompleted] session=#{sid} step=#{params.step_number} reason=#{params.finish_reason}")

    case params.finish_reason do
      reason when reason in ["stop", "tool_calls"] ->
        {:ok, signal} =
          Agentic.Signal.LLMCallComplete.new(%{
            step_id: params.step_id, run_id: params.run_id,
            step_number: params.step_number, finish_reason: reason,
            content: params[:content] || ""
          })

        {:ok, %{}, [Jido.Agent.Directive.emit(signal)]}

      "tool_executed" ->
        cm_params =
          %{step_id: params.step_id, run_id: params.run_id, step_number: params.step_number,
            entry_type: "tool_result", finish_reason: "tool_executed",
            tool_call_id: params.tool_call_id, result: params[:result]}
          |> then(&if(params[:error], do: Map.put(&1, :error, params.error), else: &1))

        {:ok, signal} = Agentic.Signal.ContextMaintain.new(cm_params)

        {:ok, %{}, [Jido.Agent.Directive.emit(signal)]}

      _ ->
        {:ok, %{}, []}
    end
  end
end
