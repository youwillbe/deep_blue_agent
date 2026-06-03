defmodule Agentic.Signal.AgentStarted do
  use Jido.Signal,
    type: "agent.started",
    schema: [],
    default_source: "action/session_created"
end
