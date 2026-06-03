defmodule Agentic.Signal.SessionCreated do
  use Jido.Signal,
    type: "session.created",
    schema: [],
    default_source: "chat/create_session"
end
