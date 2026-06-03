defmodule Agentic.Signal.StepComplete do
  use Jido.Signal,
    type: "step.complete",
    schema: [
      step_id: [type: :string],
      run_id: [type: :string],
      step_number: [type: :integer],
      finish_reason: [type: :string],
      content: [type: :string],
      tool_call_id: [type: :string],
      result: [type: :any],
      error: [type: :string]
    ],
    default_source: "action/text_received"
end
