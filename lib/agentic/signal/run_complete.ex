defmodule Agentic.Signal.RunComplete do
  use Jido.Signal,
    type: "run.complete",
    schema: [
      run_id: [type: :string],
      finish_reason: [type: :string]
    ],
    default_source: "action/text_received"
end
