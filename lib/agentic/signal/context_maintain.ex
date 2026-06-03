defmodule Agentic.Signal.ContextMaintain do
  use Jido.Signal,
    type: "context.maintain",
    schema: [
      step_id: [type: :string],
      run_id: [type: :string],
      step_number: [type: :integer],
      entry_type: [type: :string],
      finish_reason: [type: :string],
      content: [type: :string],
      tool_call_id: [type: :string],
      result: [type: :any],
      error: [type: :string]
    ],
    default_source: "action/llm_call_completed"
end
