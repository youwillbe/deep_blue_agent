defmodule Agentic.Agent do
  use Jido.Agent,
    name: "deep_blue_agent",
    schema:
      Zoi.object(%{
        session_id: Zoi.string() |> Zoi.default(""),
        system_prompt:
          Zoi.string()
          |> Zoi.default("""
          You are a concise, friendly chat assistant.
          Ask a short clarifying question when the user is ambiguous.
          Keep answers under 6 sentences unless asked to be detailed.
          """),
        model: Zoi.string() |> Zoi.default("ctyun:deepseek-v4-flash"),
        streaming_text: Zoi.string() |> Zoi.default(""),
        pid: Zoi.any(),
        tools: Zoi.any() |> Zoi.default([Agentic.Tool.Weather]),
        llm_tools: Zoi.any(),
        pending_inbox: Zoi.any() |> Zoi.default([]),
        tool_calls: Zoi.any() |> Zoi.default([]),
        context: Zoi.any() |> Zoi.default([]),
        status: Zoi.atom() |> Zoi.default(:initializing)
      }),
    signal_routes: [
      {"session.created", Agentic.Action.SessionCreated},
      {"session.resumed", Agentic.Action.SessionResumed},
      {"agent.started", Agentic.Action.AgentStarted},
      {"user.message.inbound", Agentic.Action.ReceiveUserMessage},
      {"text.received", Agentic.Action.TextReceived},
      {"text.delta.received", Agentic.Action.TextDeltaReceived},
      {"context.loaded", Agentic.Action.ContextLoaded},
      {"context.init_system_prompt", Agentic.Action.InitSystemPrompt},
      {"tool_call.received", Agentic.Action.ToolCallReceived},
      {"tool_result.received", Agentic.Action.ToolResultReceived},
      {"tools.loaded", Agentic.Action.ToolsLoaded},
      {"tool_call.args_ready", Agentic.Action.ToolCallArgsReady},
      {"tool_call.executing", Agentic.Action.ToolCallExecuting},
      {"run.start", Agentic.Action.RunStarted},
      {"run.complete", Agentic.Action.RunCompleted},
      {"step.start", Agentic.Action.StepStarted},
      {"step.complete", Agentic.Action.StepCompleted},
      {"llm_call.complete", Agentic.Action.LLMCallCompleted},
      {"context.maintain", Agentic.Action.ContextMaintained}
    ]

  def chat(pid, msg) do
    {:ok, signal} =
      Agentic.Signal.UserMessage.new(%{
        content: msg
      })

    Jido.AgentServer.cast(pid, signal)
  end
end
