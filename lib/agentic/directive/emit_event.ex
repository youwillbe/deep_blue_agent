defmodule Agentic.Directive.EmitEvent do
  @moduledoc """
  Directive to emit an event to the session's DurableStream.

  Writes messages following the Durable Streams State Protocol.
  The session_id is derived from the agent's server state, so callers
  only need to provide the entity-level fields.

  ## Fields

  - `type` - Entity type discriminator (e.g. "session", "run", "step", "user_message")
  - `key` - Unique entity identifier within its type (e.g. "run:<uuid>")
  - `operation` - "insert" | "update" | "delete"
  - `value` - The entity data (any JSON-serializable value)
  """

  defstruct [:type, :key, :operation, :value]
end

defimpl Jido.AgentServer.DirectiveExec, for: Agentic.Directive.EmitEvent do
  require Logger

  def exec(directive, _input_signal, state) do
    stream_id = "session-#{state.id}"

    message = %{
      "type" => directive.type,
      "key" => directive.key,
      "value" => directive.value,
      "headers" => %{
        "operation" => directive.operation,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    Logger.info("[Directive.EmitEvent] #{directive.operation} #{directive.type}")

    json = JSON.encode!(message)

    case DurableStreams.Server.append(stream_id, json) do
      {:ok, _offset} ->
        # Logger.info("[Directive.EmitEvent] appended offset=#{offset}")
        :ok

      {:error, reason} ->
        Logger.error("[Directive.EmitEvent] append failed: #{inspect(reason)}")
    end

    {:ok, state}
  end
end
