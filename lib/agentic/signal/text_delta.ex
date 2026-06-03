defmodule Agentic.Signal.TextDelta do
  use Jido.Signal,
    type: "text.delta.received",
    schema: [
      delta: [type: :string],
      text_id: [type: :string],
      run_id: [type: :string]
    ],
    default_source: "directive/call_llm"
end
