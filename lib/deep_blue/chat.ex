defmodule DeepBlue.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias DeepBlue.Repo

  alias DeepBlue.Chat.Session

  @doc """
  Returns the list of chat_sessions.
  """
  def list_chat_sessions do
    Session
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single session.

  Raises `Ecto.NoResultsError` if the Session does not exist.
  """
  def get_session!(id) do
    Repo.get!(Session, id)
  end

  def get_session(id) do
    case Repo.get(Session, id) do
      %Session{} = session -> {:ok, session}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Creates a session.
  """
  def create_session(attrs \\ %{}) do
    require Logger

    with {:ok, session = %Session{}} <-
           %Session{}
           |> Session.changeset(attrs)
           |> Repo.insert(),
         :ok <- ensure_stream(session),
         {:ok, _status} <- ensure_agent(session) do
      {:ok, signal} = Agentic.Signal.SessionCreated.new(%{})
      Jido.AgentServer.cast(DeepBlue.Jido.whereis(session.id), signal)

      {:ok, session}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.error("[Chat.create_session] changeset error: #{inspect(changeset.errors)}")
        {:error, changeset}

      {:error, reason} ->
        Logger.error("[Chat.create_session] failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Updates a session.
  """
  def update_session(%Session{} = session, attrs) do
    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a session.
  """
  def delete_session(%Session{} = session) do
    DeepBlue.Jido.stop_agent(session.id)
    DurableStreams.Server.delete("session-#{session.id}")
    Repo.delete(session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session changes.
  """
  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
  end

  @doc """
  Ensures the stream and agent exist for a session.
  Idempotent - safe to call on every mount.
  """
  def ensure_session(%Session{} = session) do
    stream_id = "session-#{session.id}"

    case DurableStreams.Server.create(stream_id, content_type: "application/json") do
      {:ok, _} -> :ok
      {:error, :already_exists} -> :ok
      {:error, reason} -> {:error, reason}
    end
    |> case do
      :ok ->
        case ensure_agent(session) do
          {:ok, :started} ->
            # Agent was newly started for an existing session (e.g., after restart).
            # Send SessionResumed to restore context: LoadContext → ContextLoaded → LoadTools → ToolsLoaded → idle.
            # Unlike SessionCreated, this skips session/agent lifecycle event emission.
            {:ok, signal} = Agentic.Signal.SessionResumed.new(%{})
            Jido.AgentServer.cast(DeepBlue.Jido.whereis(session.id), signal)
            :ok

          {:ok, :already_running} ->
            :ok

          err ->
            err
        end

      err ->
        err
    end
  end

  # --- Private ---

  defp ensure_agent(session) do
    case DeepBlue.Jido.whereis(session.id) do
      nil ->
        case DeepBlue.Jido.start_agent(Agentic.Agent,
               id: session.id,
               initial_state: %{session_id: session.id}
             ) do
          {:ok, _pid} -> {:ok, :started}
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        {:ok, :already_running}
    end
  end

  defp ensure_stream(session) do
    stream_id = "session-#{session.id}"

    case DurableStreams.Server.create(stream_id, content_type: "application/json") do
      {:ok, _} -> :ok
      {:error, :already_exists} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
