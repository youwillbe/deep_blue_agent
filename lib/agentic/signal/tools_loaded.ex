defmodule Agentic.Signal.ToolsLoaded do
  use Jido.Signal,
    type: "tools.loaded",
    schema: [
      llm_tools: [type: :any]
    ],
    default_source: "directive/load_tools"
end
