defmodule Agentic.Signal.ToolCall do
  use Jido.Signal,
    type: "tool_call.received",
    schema: [
      tool_call_id: [type: :string],
      tool_name: [type: :string],
      args: [type: :any],
      run_id: [type: :string],
      step_id: [type: :string],
      step_number: [type: :integer]
    ],
    default_source: "directive/call_llm"
end
