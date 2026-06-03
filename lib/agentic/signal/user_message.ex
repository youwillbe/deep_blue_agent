defmodule Agentic.Signal.UserMessage do
  use Jido.Signal,
    type: "user.message.inbound",
    schema: [
      content: [type: :string]
    ],
    default_source: "agent/chat"
end
