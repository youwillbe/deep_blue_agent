defmodule Agentic.Signal.ToolResult do
  use Jido.Signal,
    type: "tool_result.received",
    schema: [
      tool_call_id: [type: :string],
      tool_name: [type: :string],
      result: [type: :any],
      error: [type: :string],
      run_id: [type: :string],
      step_id: [type: :string],
      step_number: [type: :integer]
    ],
    default_source: "directive/call_tool"
end
