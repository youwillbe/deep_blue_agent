defmodule Agentic.Signal.RunStart do
  use Jido.Signal,
    type: "run.start",
    schema: [],
    default_source: "action/receive_user_message"
end
