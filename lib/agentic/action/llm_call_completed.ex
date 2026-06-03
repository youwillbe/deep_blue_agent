defmodule Agentic.Action.LLMCallCompleted do
  use Jido.Action,
    name: "llm_call_completed"

  require Logger

  alias Agentic.Directive.EmitEvent

  @impl true
  def run(params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.LLMCallCompleted] session=#{sid} step=#{params.step_number} reason=#{params.finish_reason}")

    llm_update = %EmitEvent{operation: "update", type: "llm_call", key: "llm_call:#{params.step_id}",
      value: %{id: "llm_call_#{params.step_id}", status: "completed", finish_reason: params.finish_reason}}

    {:ok, cm_signal} =
      Agentic.Signal.ContextMaintain.new(%{
        step_id: params.step_id, run_id: params.run_id, step_number: params.step_number,
        entry_type: "assistant", finish_reason: params.finish_reason,
        content: params[:content] || ""
      })

    {:ok, %{}, [llm_update, Jido.Agent.Directive.emit(cm_signal)]}
  end
end
