defmodule Agentic.Signal.ToolCallArgsReady do
  use Jido.Signal,
    type: "tool_call.args_ready",
    schema: [
      tool_call_id: [type: :string],
      tool_name: [type: :string],
      args: [type: :any],
      run_id: [type: :string],
      step_id: [type: :string],
      step_number: [type: :integer]
    ],
    default_source: "directive/call_tool"
end
