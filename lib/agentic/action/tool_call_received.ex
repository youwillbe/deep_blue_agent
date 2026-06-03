defmodule Agentic.Action.ToolCallReceived do
  use Jido.Action,
    name: "tool_call_received"

  require Logger

  @impl true
  def run(params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.ToolCallReceived] session=#{sid} tool=#{params.tool_name}")

    context = %{messages: ctx.state.context.messages ++ [%{role: :tool_call, name: params.tool_name, args: params.args}]}

    {:ok, %{context: context,
            tool_calls: ctx.state.tool_calls ++ [%{
              tool_call_id: params.tool_call_id,
              tool_name: params.tool_name,
              args: params.args,
              run_id: params.run_id
            }]},
     []}
  end
end
