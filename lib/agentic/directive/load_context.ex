defmodule Agentic.Directive.LoadContext do
  defstruct []
end

defimpl Jido.AgentServer.DirectiveExec, for: Agentic.Directive.LoadContext do
  require Logger

  def exec(_directive, _input_signal, state) do
    session_id = state.id
    stream_id = "session-#{session_id}"
    system_prompt = state.agent.state.system_prompt

    # Logger.info("[Directive.LoadContext] session=#{session_id}")

    agent_id = state.id
    task_sup = Jido.task_supervisor_name(state.jido)

    Task.Supervisor.start_child(task_sup, fn ->
      messages = read_stream_events(stream_id)

      context_events =
        messages
        |> Enum.filter(&(&1.type == "context"))

      if Enum.empty?(context_events) do
        Logger.info("[Directive.LoadContext] no existing context, init system prompt")

        {:ok, signal} = Agentic.Signal.InitSystemPrompt.new(%{})

        case DeepBlue.Jido.whereis(agent_id) do
          pid when is_pid(pid) -> Jido.AgentServer.cast(pid, signal)
          nil -> Logger.error("[Directive.LoadContext] agent not found: #{agent_id}")
        end
      else
        context =
          context_events
          |> Enum.reduce(%{messages: [%{role: :system, content: system_prompt}]}, fn
            %{value: %{"name" => "user", "content" => c}}, acc ->
              %{acc | messages: acc.messages ++ [%{role: :user, content: c}]}

            %{value: %{"name" => "assistant", "content" => c}}, acc ->
              %{acc | messages: acc.messages ++ [%{role: :assistant, content: c}]}

            _, acc ->
              acc
          end)

        Logger.info("[Directive.LoadContext] context loaded")

        {:ok, signal} = Agentic.Signal.ContextLoaded.new(%{context: context})

        case DeepBlue.Jido.whereis(agent_id) do
          pid when is_pid(pid) -> Jido.AgentServer.cast(pid, signal)
          nil -> Logger.error("[Directive.LoadContext] agent not found: #{agent_id}")
        end
      end
    end)

    {:async, nil, state}
  end

  defp read_stream_events(stream_id) do
    case DurableStreams.Server.read_messages(stream_id, "0") do
      {:ok, %{messages: messages}} ->
        Enum.map(messages, fn msg ->
          decoded = JSON.decode!(msg.data)
          %{type: decoded["type"], value: decoded["value"]}
        end)

      _ ->
        []
    end
  end
end
