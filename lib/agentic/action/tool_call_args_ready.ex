defmodule Agentic.Action.ToolCallArgsReady do
  use Jido.Action,
    name: "tool_call_args_ready"

  require Logger

  alias Agentic.Directive.{ExecTool, EmitEvent}

  @impl true
  def run(params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.ToolCallArgsReady] session=#{sid} tool=#{params.tool_name}")

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
           status: "args_complete",
           args: params.args
         }
       },
       %ExecTool{
         tool_call_id: params.tool_call_id,
         tool_name: params.tool_name,
         args: params.args,
         run_id: params.run_id,
         step_id: params.step_id,
         step_number: params.step_number
       }
     ]}
  end
end
