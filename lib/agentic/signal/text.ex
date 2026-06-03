defmodule Agentic.Signal.Text do
  use Jido.Signal,
    type: "text.received",
    schema: [
      run_id: [type: :string],
      step_id: [type: :string],
      step_number: [type: :integer],
      error: [type: :string],
      done: [type: :boolean],
      finish_reason: [type: :string]
    ],
    default_source: "directive/call_llm"
end
