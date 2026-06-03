defmodule Agentic.Action.TextReceived do
  use Jido.Action,
    name: "text_received"

  require Logger

  alias Agentic.Directive.EmitEvent

  @impl true
  def run(params, ctx) do
    sid = ctx.state.session_id
    done = Map.get(params, :done, true)

    Logger.info("[Action.TextReceived] session=#{sid} run=#{params.run_id} done=#{done}")

    if Map.has_key?(params, :error) do
      {:ok, %{},
       [
         %EmitEvent{operation: "insert", type: "error", key: "error:#{params.step_id}",
           value: %{id: "error_#{UUIDv7.generate()}", error_code: "LLM_ERROR",
             message: params.error, run_id: params.run_id, step_id: params.step_id}}
       ]}
    else
      text_id = "text_#{params.step_id}"

      text_event = %EmitEvent{operation: (done && "update") || "insert", type: "text",
        key: "text:#{params.step_id}",
        value: %{id: text_id, run_id: params.run_id, status: (done && "completed") || "streaming"}}

      if done do
        content = String.trim_trailing(ctx.state.streaming_text, "\n")

        {:ok, step_complete} =
          Agentic.Signal.StepComplete.new(%{
            step_id: params.step_id, run_id: params.run_id,
            step_number: params.step_number, finish_reason: params[:finish_reason],
            content: content
          })

        directives = [text_event]
        directives = if content != "",
          do: directives ++ [%EmitEvent{operation: "insert", type: "context", key: "context:#{UUIDv7.generate()}",
                value: %{id: UUIDv7.generate(), name: "assistant", attrs: %{}, content: content,
                  timestamp: DateTime.utc_now() |> DateTime.to_iso8601()}}],
          else: directives
        directives = directives ++ [Jido.Agent.Directive.emit(step_complete)]

        {:ok, %{streaming_text: ""}, directives}
      else
        {:ok, %{status: :step_running}, [text_event]}
      end
    end
  end
end
