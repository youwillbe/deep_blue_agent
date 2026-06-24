defmodule Agentic.Signal.SessionResumed do
  use Jido.Signal,
    type: "session.resumed",
    schema: [],
    default_source: "chat/ensure_session"
end
