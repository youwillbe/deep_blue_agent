defmodule Agentic.Core.State do
  defstruct [
    :id,
    :turn_id,
    :current_msg,
    status: :idle,
    stream: true,
    pending_messages: [],
    step_count: 0,
    max_steps: 10,
    pending_tool_calls: [],
    last_error: nil,
    response: nil,
    context: nil
  ]

  @type status ::
          :idle
          | :thinking
          | :planning
          | :executing
          | :evaluating
          | :generating_response
          | :waiting_user
          | :waiting_approval
          | :completed
          | :error

  @type step_type ::
          :planning
          | :tool_execution
          | :evaluation
          | :generating_response
          | :waiting_input
          | :approval
end
