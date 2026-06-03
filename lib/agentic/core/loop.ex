defmodule Agentic.Core.Loop do
  # alias Agentic.Core.{State, Msg, Cmd, Event}

  # import ReqLLM.Context, only: [system: 1, user: 1]
  # alias ReqLLM.Context

  # @moduledoc """
  # Loop 为纯函数状态机，模式为扩展的 TEA 架构

  # State + Msg -> State' + Cmd + Event

  # | Msg                                              | → 通常在什么状态下处理            | → 产生的 Cmd/Event                                                                       |
  # | ------------------------------------------------ | --------------------------------- | ---------------------------------------------------------------------------------------- |
  # | {:user_message, content}                         | :idle                             | → 进入 thinking，发起 :call_llm 规划，生成事件                                           |
  # | {:user_input_provided, step_id, data}            | :waiting_user                     | → 结束等待，继续执行后续步骤，生成 UserInputProvided                                     |
  # | {:tool_result, ref, {:ok, result}}               | :thinking                         | → 工具成功，生成 ToolCallResultReceived，继续决策下一步                                  |
  # | {:tool_result, ref, {:error, reason}}            | :thinking                         | → 工具失败，生成 ToolCallFailed，错误处理或重试                                          |
  # | {:llm_chunk, step_id, delta}                     | :thinking (流式生成中)            | → 生成 AgentStepProgress/AgentResponseDelta，发送 :send_response_delta                   |
  # | {:llm_done, step_id, full, usage}                | :thinking (流式完成)              | → 生成 AgentStepCompleted/AgentResponseGenerated，发送 :send_response，回到 :idle 或继续 |
  # | {:llm_error, step_id, reason}                    | :thinking                         | → 生成 AgentError/AgentStepFailed，错误处理                                              |
  # | {:approval_response, step_id, approved, comment} | :waiting_approval                 | → 生成 ApprovalGranted/Denied，继续执行或回退                                            |
  # | :continue                                        | :thinking (内部链式调用)          | → 推进状态机（如完成某步骤后自动开始下一个步骤）                                         |
  # | :timeout                                         | :waiting_user / :waiting_approval | → 超时处理，可能生成错误事件并放弃等待                                                   |
  # """

  # ##################################################
  # ### region INIT

  # @doc """
  # init() -> S: :idle + E: [:session_started]
  # """
  # def init(session_id) do
  #   context = Context.new([system("You are a helpful assistant.")])

  #   state = %State{
  #     id: session_id,
  #     status: :idle,
  #     context: context
  #   }

  #   {state, [], [Event.initialized(session_id)]}
  # end

  # ### endregion
  # ##################################################

  # ##################################################
  # ### region UPDATE

  # def update(%State{status: :idle} = state, {:user_message, content}) do
  #   turn_id = Uniq.UUID.uuid7()
  #   context = Context.append(state.context, user(content))

  #   new_state = %{
  #     state
  #     | status: :calling_llm,
  #       current_msg: content,
  #       turn_id: turn_id,
  #       step_count: 1,
  #       response: nil,
  #       context: context
  #   }

  #   cmd = if state.stream, do: Cmd.call_llm_stream(), else: Cmd.call_llm()

  #   events = [
  #     Event.turn_started(turn_id),
  #     Event.user_message(turn_id, content),
  #     Event.call_llm_started(turn_id)
  #   ]

  #   {new_state, [cmd], events}
  # end

  # # def update(%State{status: status} = state, %Msg{type: :inbound, payload: content})
  # #     when status != :idle do
  # #   {%{state | pending_messages: state.pending_messages ++ [content]}, [], []}
  # # end

  # # def update(%State{status: :calling_llm} = state, %Msg{type: :llm_response, payload: res}) do
  # #   context = Context.merge_response(state.context, res).context
  # #   turn_id = state.turn_id

  # #   case res.finish_reason do
  # #     :stop ->
  # #       thinking = extract_thinking(res.message.content)
  # #       text = extract_text(res.message.content)

  # #       new_state = %{
  # #         state
  # #         | status: :idle,
  # #           step_count: 0,
  # #           response: res.message.content,
  # #           context: context
  # #       }

  # #       events =
  # #         []
  # #         |> then(fn e ->
  # #           if thinking, do: e ++ [Event.think_message(turn_id, thinking)], else: e
  # #         end)
  # #         |> Kernel.++([Event.response_message(turn_id, text)])
  # #         |> Kernel.++([Event.call_llm_finished(turn_id)])

  # #       {new_state, [Cmd.end_turn()], events}

  # #     :tool_calls ->
  # #       if state.step_count >= state.max_steps do
  # #         reason = "max_steps exceeded"

  # #         new_state = %{
  # #           state
  # #           | status: :idle,
  # #             step_count: 0,
  # #             last_error: %{reason: reason}
  # #         }

  # #         {new_state, [Cmd.error()], [Event.agent_error(turn_id, reason)]}
  # #       else
  # #         tool_calls = res.message.tool_calls || []
  # #         new_state = %{state | status: :calling_tools, pending_tool_calls: tool_calls}
  # #         {new_state, [Cmd.exec_tool()], []}
  # #       end

  # #     _ ->
  # #       reason = "Unsupported finish reason."

  # #       new_state = %{
  # #         state
  # #         | status: :idle,
  # #           step_count: 0,
  # #           last_error: %{reason: reason}
  # #       }

  # #       {new_state, [Cmd.error()], [Event.agent_error(turn_id, reason)]}
  # #   end
  # # end

  # # def update(
  # #       %State{status: :calling_tools} = state,
  # #       %Msg{type: :tool_result, payload: {_tool_use_id, _result}}
  # #     ) do
  # #   new_state = %{
  # #     state
  # #     | status: :calling_llm,
  # #       step_count: state.step_count + 1,
  # #       pending_tool_calls: []
  # #   }

  # #   {new_state, [Cmd.call_llm()], [Event.call_llm_started(state.turn_id)]}
  # # end

  # ### endregion
  # ##################################################

  # ##################################################
  # ### region DEQUEUE

  # def dequeue(%State{pending_messages: []} = state) do
  #   tid = state.turn_id
  #   new_state = %{state | current_msg: nil, turn_id: nil}
  #   {new_state, [], [Event.turn_completed(tid)]}
  # end

  # def dequeue(%State{pending_messages: [msg | rest]} = state) do
  #   old_turn_id = state.turn_id

  #   {new_state, cmds, events} =
  #     update(%{state | pending_messages: rest, status: :idle}, Msg.inbound(msg))

  #   {new_state, cmds, [Event.turn_completed(old_turn_id) | events]}
  # end

  # ### endregion
  # ##################################################

  # ##################################################
  # ### region PRIVATE FUNCTION

  # defp extract_text(content) when is_list(content) do
  #   content
  #   |> Enum.filter(&(&1.type == :text))
  #   |> Enum.map_join(& &1.text)
  #   |> String.trim_leading()
  # end

  # defp extract_text(_), do: nil

  # defp extract_thinking(content) when is_list(content) do
  #   content
  #   |> Enum.filter(&(&1.type == :thinking))
  #   |> Enum.map_join(& &1.text)
  #   |> String.trim_leading()
  # end

  # defp extract_thinking(_), do: nil

  # ### endregion
  # ##################################################
end
