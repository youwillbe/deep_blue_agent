defmodule Agentic.Signal.InitSystemPrompt do
  use Jido.Signal,
    type: "context.init_system_prompt",
    schema: [],
    default_source: "directive/load_context"
end
