defmodule Agentic.Signal.StepStart do
  use Jido.Signal,
    type: "step.start",
    schema: [
      step_id: [type: :string],
      run_id: [type: :string],
      step_number: [type: :integer],
      step_type: [type: :string],
      tool_call_id: [type: :string],
      tool_name: [type: :string],
      args: [type: :any]
    ],
    default_source: "action/run_started"
end
