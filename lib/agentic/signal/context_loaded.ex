defmodule Agentic.Signal.ContextLoaded do
  use Jido.Signal,
    type: "context.loaded",
    schema: [
      context: [type: :any]
    ],
    default_source: "directive/load_context"
end
