defmodule Agentic.Action.ToolCallExecuting do
  use Jido.Action,
    name: "tool_call_executing"

  require Logger

  alias Agentic.Directive.EmitEvent

  @impl true
  def run(params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.ToolCallExecuting] session=#{sid} tool=#{params.tool_name}")

    {:ok, %{},
     [
       %EmitEvent{
         operation: "update",
         type: "tool_call",
         key: "tool_call:#{params.tool_call_id}",
         value: %{
           tool_call_id: params.tool_call_id,
           run_id: params.run_id,
           tool_name: params.tool_name,
           status: "executing"
         }
       }
     ]}
  end
end
