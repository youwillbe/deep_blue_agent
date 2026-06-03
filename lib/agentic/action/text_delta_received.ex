defmodule Agentic.Action.TextDeltaReceived do
  use Jido.Action,
    name: "text_delta_received"

  require Logger

  alias Agentic.Directive.EmitEvent

  @impl true
  def run(params, ctx) do
    Logger.info("[Action.TextDeltaReceived] text_id=#{params.text_id}")

    {:ok, %{streaming_text: ctx.state.streaming_text <> params.delta},
     [
       %EmitEvent{
         operation: "insert",
         type: "text_delta",
         key: "text_delta:#{UUIDv7.generate()}",
         value: %{
           id: UUIDv7.generate(),
           text_id: params.text_id,
           run_id: params.run_id,
           delta: params.delta
         }
       }
     ]}
  end
end
