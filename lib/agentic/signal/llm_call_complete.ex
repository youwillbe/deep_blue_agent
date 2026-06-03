defmodule Agentic.Signal.LLMCallComplete do
  use Jido.Signal,
    type: "llm_call.complete",
    schema: [
      step_id: [type: :string],
      run_id: [type: :string],
      step_number: [type: :integer],
      finish_reason: [type: :string],
      content: [type: :string]
    ],
    default_source: "action/step_completed"
end
