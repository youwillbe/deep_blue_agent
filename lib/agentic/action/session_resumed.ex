defmodule Agentic.Action.SessionResumed do
  use Jido.Action,
    name: "session_resumed"

  require Logger

  @impl true
  def run(_params, ctx) do
    sid = ctx.state.session_id

    Logger.info("[Action.SessionResumed] session=#{sid}")

    # Skip session/agent lifecycle events — the session already exists.
    # Go directly to LoadContext which reads existing context from the stream.
    {:ok, %{}, [%Agentic.Directive.LoadContext{}]}
  end
end
