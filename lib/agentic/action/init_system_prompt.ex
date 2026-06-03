defmodule Agentic.Action.InitSystemPrompt do
  use Jido.Action,
    name: "init_system_prompt"

  require Logger

  alias Agentic.Directive.EmitEvent

  @impl true
  def run(_params, ctx) do
    Logger.info("[Action.InitSystemPrompt] session=#{ctx.state.session_id}")

    {:ok, %{context: %{messages: [%{role: :system, content: ctx.state.system_prompt}]}},
     [
       %EmitEvent{
         operation: "insert",
         type: "context",
         key: "context:#{UUIDv7.generate()}",
         value: %{
           id: UUIDv7.generate(),
           name: "system",
           attrs: %{},
           content: ctx.state.system_prompt,
           timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
         }
       },
       %Agentic.Directive.LoadTools{}
     ]}
  end
end
