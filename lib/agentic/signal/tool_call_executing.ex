defmodule Agentic.Signal.ToolCallExecuting do
  use Jido.Signal,
    type: "tool_call.executing",
    schema: [
      tool_call_id: [type: :string],
      tool_name: [type: :string],
      run_id: [type: :string],
      step_id: [type: :string],
      step_number: [type: :integer]
    ],
    default_source: "directive/exec_tool"
end
