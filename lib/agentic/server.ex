defmodule Agentic.Server do
  # use GenServer

  # alias Agentic.Core.{Loop, State, Msg, Cmd, Event}

  # ##################################################
  # ### region DURABLE SERVER CALLBACKS

  # @impl true
  # def init(%State{} = state) do
  #   load_history_into_stream(state.id)
  #   {:ok, state}
  # end

  # ### endregion
  # ##################################################

  # ##################################################
  # ### region CLIENT API

  # def ensure_started(session_id) do
  #   key = "session/#{session_id}"

  #   case DurableServer.Supervisor.lookup(AgentSup, key) do
  #     {pid, _meta} ->
  #       {:ok, pid}

  #     nil ->
  #       DurableServer.Supervisor.start_child(
  #         AgentSup,
  #         {__MODULE__, key: key, initial_state: %State{id: session_id}}
  #       )
  #   end
  # end

  # def send_message(session_id, msg) do
  #   case DurableServer.Supervisor.lookup(AgentSup, "session/#{session_id}") do
  #     {pid, _meta} -> GenServer.cast(pid, {:run_stream, msg})
  #     nil -> {:error, :not_found}
  #   end
  # end

  # def get_state(session_id) do
  #   case DurableServer.Supervisor.lookup(AgentSup, "session/#{session_id}") do
  #     {pid, _meta} -> GenServer.call(pid, :get_state)
  #     nil -> nil
  #   end
  # end

  # def stop(session_id) do
  #   case DurableServer.Supervisor.lookup(AgentSup, "session/#{session_id}") do
  #     {pid, _meta} ->
  #       try do
  #         GenServer.stop(pid, :normal)
  #       catch
  #         :exit, _ -> :ok
  #       end

  #     nil ->
  #       :ok
  #   end
  # end

  # ### endregion
  # ##################################################

  # ##################################################
  # ### region SERVER CALLBACKS

  # @impl true
  # def handle_call(:get_state, _from, state) do
  #   {:reply, state, state}
  # end

  # @impl true
  # def handle_cast({:run_stream, msg}, state) do
  #   inbound_msg = Msg.inbound(msg)
  #   {new_state, cmds, events} = Loop.update(state, inbound_msg)

  #   all_events = [Event.user_message_received(msg) | events]
  #   persist_from_events(new_state.id, all_events)
  #   emit_events(new_state.id, all_events)

  #   {:noreply, new_state, {:continue, {:exec_cmds, cmds}}}
  # end

  # @impl true
  # def handle_info({:llm_called, res}, state) do
  #   llm_msg = Msg.llm_response(res)
  #   {new_state, cmds, events} = Loop.update(state, llm_msg)

  #   persist_from_events(new_state.id, events)
  #   emit_events(new_state.id, events)

  #   {:noreply, new_state, {:continue, {:exec_cmds, cmds}}}
  # end

  # @impl true
  # def handle_info({:tool_executed, tool_use_id, result}, state) do
  #   msg = Msg.tool_result(tool_use_id, result)
  #   {new_state, cmds, events} = Loop.update(state, msg)

  #   emit_events(new_state.id, events)
  #   {:noreply, new_state, {:continue, {:exec_cmds, cmds}}}
  # end

  # @impl true
  # def handle_info({:turn_completed}, state) do
  #   {new_state, cmds, events} = Loop.dequeue(state)

  #   persist_from_events(new_state.id, events)
  #   emit_events(new_state.id, events)

  #   {:noreply, new_state, {:continue, {:exec_cmds, cmds}}}
  # end

  # @impl true
  # def handle_continue({:exec_cmds, cmds}, state) do
  #   Enum.each(cmds, &exec_cmd(&1, state))
  #   {:noreply, state}
  # end

  # ### endregion
  # ##################################################

  # ##################################################
  # ### region PRIVATE FUNCTION

  # # --- Event dispatch ---

  # defp emit_events(session_id, events) do
  #   Enum.each(events, &emit_event(session_id, &1))
  # end

  # defp emit_event(_session_id, %Event{type: :initialized}), do: :ok
  # defp emit_event(_session_id, %Event{type: :user_message_received}), do: :ok

  # defp emit_event(session_id, %Event{type: :turn_started, data: %{turn_id: tid}}) do
  #   emit(session_id, "turn_started", %{turn_id: tid})
  # end

  # defp emit_event(session_id, %Event{type: :user_message, data: %{turn_id: tid, content: content}}) do
  #   emit(session_id, "user_message", %{turn_id: tid, content: content})
  # end

  # defp emit_event(session_id, %Event{type: :call_llm_started, data: %{turn_id: tid}}) do
  #   emit(session_id, "call_llm_started", %{turn_id: tid})
  # end

  # defp emit_event(session_id, %Event{
  #        type: :think_message,
  #        data: %{turn_id: tid, content: content}
  #      }) do
  #   emit(session_id, "think_message", %{turn_id: tid, content: content})
  # end

  # defp emit_event(session_id, %Event{
  #        type: :response_message,
  #        data: %{turn_id: tid, content: content}
  #      }) do
  #   emit(session_id, "response_message", %{turn_id: tid, content: content})
  # end

  # defp emit_event(session_id, %Event{type: :call_llm_finished, data: %{turn_id: tid}}) do
  #   emit(session_id, "call_llm_finished", %{turn_id: tid})
  # end

  # defp emit_event(session_id, %Event{type: :turn_completed, data: %{turn_id: tid}}) do
  #   emit(session_id, "turn_completed", %{turn_id: tid})
  # end

  # defp emit_event(session_id, %Event{type: :agent_error, data: %{turn_id: tid, reason: reason}}) do
  #   emit(session_id, "agent_error", %{turn_id: tid, reason: reason})
  # end

  # # --- History persistence from events ---

  # defp persist_from_events(session_id, events) do
  #   Enum.each(events, &persist_from_event(session_id, &1))
  # end

  # defp persist_from_event(_session_id, %Event{type: :initialized}), do: :ok
  # defp persist_from_event(_session_id, %Event{type: :user_message_received}), do: :ok
  # defp persist_from_event(_session_id, %Event{type: :turn_completed}), do: :ok

  # defp persist_from_event(session_id, %Event{type: :turn_started, data: %{turn_id: tid}}) do
  #   persist_history(session_id, "turn_started", %{}, tid)
  # end

  # defp persist_from_event(session_id, %Event{
  #        type: :user_message,
  #        data: %{turn_id: tid, content: content}
  #      }) do
  #   persist_history(session_id, "user_message", %{content: content}, tid)
  # end

  # defp persist_from_event(session_id, %Event{type: :call_llm_started, data: %{turn_id: tid}}) do
  #   persist_history(session_id, "call_llm_started", %{}, tid)
  # end

  # defp persist_from_event(session_id, %Event{
  #        type: :think_message,
  #        data: %{turn_id: tid, content: content}
  #      }) do
  #   persist_history(session_id, "think_message", %{content: content}, tid)
  # end

  # defp persist_from_event(session_id, %Event{
  #        type: :response_message,
  #        data: %{turn_id: tid, content: content}
  #      }) do
  #   persist_history(session_id, "response_message", %{content: content}, tid)
  # end

  # defp persist_from_event(session_id, %Event{type: :call_llm_finished, data: %{turn_id: tid}}) do
  #   persist_history(session_id, "call_llm_finished", %{}, tid)
  # end

  # defp persist_from_event(session_id, %Event{
  #        type: :agent_error,
  #        data: %{turn_id: tid, reason: reason}
  #      }) do
  #   persist_history(session_id, "agent_error", %{reason: reason}, tid)
  # end

  # defp emit(session_id, event_type, data) do
  #   require Logger
  #   stream_id = "session-#{session_id}"
  #   payload = Jason.encode!(%{"type" => event_type, "data" => data})
  #   {:ok, offset} = ensure_append(stream_id, payload)

  #   Logger.debug(
  #     "[emit] #{event_type} | session=#{session_id} offset=#{offset} data=#{inspect(data)}"
  #   )

  #   broadcast(session_id, {:stream_event, event_type, data, offset})
  # end

  # # --- Cmd execution ---

  # defp exec_cmd(%Cmd{type: :call_llm_stream}, state) do
  #   me = self()

  #   Task.start(fn ->
  #     case Agentic.LLM.call_stream(state.context) do
  #       {:error, error} ->
  #         emit(state.id, "error", %{reason: inspect(error)})

  #       stream_res ->
  #         case ReqLLM.StreamResponse.process_stream(stream_res,
  #                on_result: fn text_delta ->
  #                  emit(state.id, "stream_delta", %{text: trim_first(text_delta, :result)})
  #                end,
  #                on_thinking: fn thinking_delta ->
  #                  emit(state.id, "thinking_delta", %{text: trim_first(thinking_delta, :thinking)})
  #                end
  #              ) do
  #           {:ok, response} ->
  #             send(me, {:llm_called, response})

  #           {:error, error} ->
  #             emit(state.id, "error", %{reason: inspect(error)})
  #         end
  #     end
  #   end)
  # end

  # defp exec_cmd(%Cmd{type: :call_llm}, state) do
  #   me = self()

  #   Task.start(fn ->
  #     res = Agentic.LLM.call(state.context)
  #     send(me, {:llm_called, res})
  #   end)
  # end

  # defp exec_cmd(%Cmd{type: :end_turn}, _state) do
  #   send(self(), {:turn_completed})
  # end

  # defp exec_cmd(%Cmd{type: :exec_tool}, state) do
  #   me = self()
  #   tool_calls = state.pending_tool_calls

  #   Task.start(fn ->
  #     Enum.each(tool_calls, fn tc ->
  #       result = execute_tool_call(tc)
  #       send(me, {:tool_executed, tc.id, result})
  #     end)
  #   end)
  # end

  # defp exec_cmd(%Cmd{type: :error}, _state) do
  #   :ok
  # end

  # defp execute_tool_call(_tc) do
  #   "tool result placeholder"
  # end

  # # --- History persistence ---

  # defp persist_history(session_id, type, payload, turn_id) do
  #   attrs = %{
  #     id: Uniq.UUID.uuid7(),
  #     session_id: session_id,
  #     type: type,
  #     payload: payload,
  #     turn_id: turn_id
  #   }

  #   case DeepBlue.Chat.create_history(attrs) do
  #     {:ok, _} ->
  #       :ok

  #     {:error, changeset} ->
  #       require Logger

  #       Logger.error("Failed to persist history: #{inspect(changeset.errors)}")
  #   end
  # end

  # # --- Streamkeeper ---

  # defp ensure_append(stream_id, data) do
  #   case DurableStreams.StreamManager.append(stream_id, data) do
  #     {:ok, offset} ->
  #       {:ok, offset}

  #     {:error, :not_found} ->
  #       case DurableStreams.StreamManager.create(stream_id, content_type: "application/json") do
  #         {:ok, _} ->
  #           DurableStreams.StreamManager.append(stream_id, data)

  #         {:error, :already_exists} ->
  #           DurableStreams.StreamManager.append(stream_id, data)
  #       end

  #     {:error, reason} ->
  #       require Logger
  #       Logger.error("Failed to append to stream: #{inspect(reason)}")
  #       {:error, reason}
  #   end
  # end

  # defp load_history_into_stream(session_id) do
  #   stream_id = "session-#{session_id}"

  #   case DurableStreams.StreamManager.get_metadata(stream_id) do
  #     {:ok, _} ->
  #       :ok

  #     {:error, :not_found} ->
  #       case DurableStreams.StreamManager.create(stream_id, content_type: "application/json") do
  #         {:ok, _} ->
  #           histories = DeepBlue.Chat.list_histories(session_id)

  #           Enum.each(histories, fn history ->
  #             event =
  #               Jason.encode!(%{
  #                 "type" => history.type,
  #                 "data" => history.payload,
  #                 "turn_id" => history.turn_id
  #               })

  #             DurableStreams.StreamManager.append(stream_id, event)
  #           end)

  #         {:error, :already_exists} ->
  #           :ok
  #       end
  #   end
  # end

  # # --- Context serialization ---

  # defp serialize_context(nil), do: []

  # defp serialize_context(%ReqLLM.Context{} = context) do
  #   context |> ReqLLM.Context.to_list() |> Enum.map(&serialize_message/1)
  # end

  # defp serialize_message(%ReqLLM.Message{role: role, content: content, tool_calls: tool_calls}) do
  #   %{
  #     "role" => to_string(role),
  #     "content" => serialize_content(content),
  #     "tool_calls" => tool_calls
  #   }
  # end

  # defp serialize_message(msg) when is_map(msg), do: msg

  # defp serialize_content(content) when is_list(content) do
  #   Enum.map(content, fn
  #     %{type: :text, text: text} -> %{"type" => "text", "text" => text}
  #     %{type: :thinking, text: text} -> %{"type" => "thinking", "text" => text}
  #     other -> other
  #   end)
  # end

  # defp serialize_content(content), do: content

  # defp deserialize_context(nil), do: ReqLLM.Context.new()

  # defp deserialize_context(messages) when is_list(messages) do
  #   messages
  #   |> Enum.map(&deserialize_message/1)
  #   |> ReqLLM.Context.new()
  # end

  # defp deserialize_message(%{"role" => role, "content" => content, "tool_calls" => tool_calls}) do
  #   %ReqLLM.Message{
  #     role: String.to_existing_atom(role),
  #     content: deserialize_content(content),
  #     tool_calls: tool_calls
  #   }
  # end

  # defp deserialize_message(msg), do: msg

  # defp deserialize_content(content) when is_list(content) do
  #   Enum.map(content, fn
  #     %{"type" => "text", "text" => text} -> %{type: :text, text: text}
  #     %{"type" => "thinking", "text" => text} -> %{type: :thinking, text: text}
  #     other -> other
  #   end)
  # end

  # defp deserialize_content(content), do: content

  # # --- Helpers ---

  # defp trim_first(text, key) do
  #   if Process.get({:stream_started, key}) do
  #     text
  #   else
  #     Process.put({:stream_started, key}, true)
  #     String.trim_leading(text)
  #   end
  # end

  # # --- Broadcast ---

  # defp broadcast(session_id, msg) do
  #   Phoenix.PubSub.broadcast(DeepBlue.PubSub, "session:#{session_id}:stream", msg)
  # end

  # ### endregion
  # ##################################################
end
