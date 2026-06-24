defmodule DurableStreams.Server do
  @moduledoc """
  GenServer managing a single stream's lifecycle.

  Each stream is managed by its own GenServer process, providing:
  - Process isolation for fault tolerance
  - Stateful management of waiters for long-polling
  - Automatic TTL expiration handling
  """

  use GenServer, restart: :transient

  alias DurableStreams.Stream

  defstruct [:stream_id, :storage, :waiters]

  ##################################################
  ### region Client API

  def create(stream_id, opts \\ []) do
    opts = ensure_storage(opts)

    with {:ok, _pid} <-
           DynamicSupervisor.start_child(
             DurableStreams.StreamSupervisor,
             {__MODULE__, {stream_id, opts}}
           ) do
      {:ok, stream_id}
    else
      {:error, {:already_started, _pid}} -> {:error, :already_exists}
      {:error, :already_exists} -> {:error, :already_exists}
      error -> error
    end
  end

  def append(stream_id, data, opts \\ []) do
    GenServer.call(via_tuple(stream_id), {:append, data, opts})
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def read(stream_id, offset, opts \\ []) do
    live = Keyword.get(opts, :live, false)
    timeout = Keyword.get(opts, :timeout, 30_000)

    GenServer.call(via_tuple(stream_id), {:read, offset, live, timeout}, timeout + 5_000)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def close(stream_id) do
    GenServer.call(via_tuple(stream_id), :close)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def delete(stream_id) do
    case Registry.lookup(DurableStreams.Registry, stream_id) do
      [{pid, _}] ->
        storage = GenServer.call(via_tuple(stream_id), :get_storage)

        # Close first if still open, so SSE clients receive streamClosed
        {:ok, meta} = GenServer.call(via_tuple(stream_id), :get_metadata)
        if !meta.closed, do: GenServer.call(via_tuple(stream_id), :close)

        DynamicSupervisor.terminate_child(DurableStreams.StreamSupervisor, pid)
        storage.delete(stream_id)

      [] ->
        {:error, :not_found}
    end
  end

  def get_metadata(stream_id) do
    GenServer.call(via_tuple(stream_id), :get_metadata)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def current_offset(stream_id) do
    GenServer.call(via_tuple(stream_id), :current_offset)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def read_messages(stream_id, offset, opts \\ []) do
    live = Keyword.get(opts, :live, false)
    timeout = Keyword.get(opts, :timeout, 30_000)

    GenServer.call(via_tuple(stream_id), {:read_messages, offset, live, timeout}, timeout + 5_000)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def start_link({stream_id, opts}) do
    GenServer.start_link(__MODULE__, {stream_id, opts}, name: via_tuple(stream_id))
  end

  ### endregion
  ##################################################

  ##################################################
  ### region Init

  @impl GenServer
  def init({stream_id, opts}) do
    storage = Keyword.fetch!(opts, :storage)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    ttl = Keyword.get(opts, :ttl)
    expires_at = Keyword.get(opts, :expires_at)

    stream = Stream.new(stream_id, content_type: content_type, ttl: ttl, expires_at: expires_at)

    case storage.create(stream_id, stream) do
      :ok ->
        Phoenix.PubSub.subscribe(DurableStreams.PubSub, "stream:#{stream_id}")
        schedule_expiration(ttl, expires_at)
        {:ok, %__MODULE__{stream_id: stream_id, storage: storage, waiters: []}}

      {:error, :already_exists} ->
        # Stream already exists in persistent storage (e.g., after restart).
        # Load the existing metadata and continue normally.
        {:ok, existing_stream} = storage.get_metadata(stream_id)

        Phoenix.PubSub.subscribe(DurableStreams.PubSub, "stream:#{stream_id}")
        schedule_expiration(existing_stream.ttl, existing_stream.expires_at)

        {:ok, %__MODULE__{stream_id: stream_id, storage: storage, waiters: []}}
    end
  end

  ### endregion
  ##################################################

  ##################################################
  ### region Handle Call

  @impl GenServer
  def handle_call({:append, data, opts}, _from, state) do
    seq = Keyword.get(opts, :seq)

    case state.storage.append(state.stream_id, data, seq) do
      {:ok, offset} = result ->
        Phoenix.PubSub.broadcast(
          DurableStreams.PubSub,
          "stream:#{state.stream_id}",
          {:stream_append, state.stream_id, offset}
        )

        {:reply, result, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:read, offset, false, _timeout}, _from, state) do
    result = state.storage.read(state.stream_id, offset)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:read, offset, true, timeout}, from, state) do
    case state.storage.read(state.stream_id, offset) do
      {:ok, %{data: <<>>} = result} when not result.closed ->
        timer_ref = Process.send_after(self(), {:waiter_timeout, from}, timeout)
        waiter = {from, offset, timer_ref}
        {:noreply, %{state | waiters: [waiter | state.waiters]}}

      result ->
        {:reply, result, state}
    end
  end

  @impl GenServer
  def handle_call(:close, _from, state) do
    case state.storage.close(state.stream_id) do
      :ok = result ->
        # Reply to waiters synchronously so SSE clients receive streamClosed
        # before the process is potentially terminated by delete
        for waiter <- state.waiters do
          reply_to_waiter(waiter, state)
        end

        Phoenix.PubSub.broadcast(
          DurableStreams.PubSub,
          "stream:#{state.stream_id}",
          {:stream_closed, state.stream_id}
        )

        {:reply, result, %{state | waiters: []}}

      error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call(:get_metadata, _from, state) do
    result = state.storage.get_metadata(state.stream_id)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:get_storage, _from, state) do
    {:reply, state.storage, state}
  end

  @impl GenServer
  def handle_call(:current_offset, _from, state) do
    result = state.storage.current_offset(state.stream_id)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:read_messages, offset, false, _timeout}, _from, state) do
    result = state.storage.read_messages(state.stream_id, offset)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:read_messages, offset, true, timeout}, from, state) do
    case state.storage.read_messages(state.stream_id, offset) do
      {:ok, %{messages: []} = result} when not result.closed ->
        timer_ref = Process.send_after(self(), {:waiter_timeout_messages, from, offset}, timeout)
        waiter = {from, offset, timer_ref, :messages}
        {:noreply, %{state | waiters: [waiter | state.waiters]}}

      result ->
        {:reply, result, state}
    end
  end

  ### endregion
  ##################################################

  ##################################################
  ### region Handle Info

  @impl GenServer
  def handle_info({:stream_append, _stream_id, _offset}, state) do
    for waiter <- state.waiters do
      reply_to_waiter(waiter, state)
    end

    {:noreply, %{state | waiters: []}}
  end

  @impl GenServer
  def handle_info({:stream_closed, _stream_id}, state) do
    for waiter <- state.waiters do
      reply_to_waiter(waiter, state)
    end

    {:noreply, %{state | waiters: []}}
  end

  @impl GenServer
  def handle_info({:waiter_timeout, from}, state) do
    {waiter, remaining} =
      Enum.split_with(state.waiters, fn
        {f, _, _} -> f == from
        {f, _, _, _} -> f == from
      end)

    case waiter do
      [w] -> reply_to_waiter(w, state)
      _ -> :ok
    end

    {:noreply, %{state | waiters: remaining}}
  end

  @impl GenServer
  def handle_info({:waiter_timeout_messages, from, _offset}, state) do
    {waiter, remaining} =
      Enum.split_with(state.waiters, fn
        {f, _, _} -> f == from
        {f, _, _, _} -> f == from
      end)

    case waiter do
      [w] -> reply_to_waiter(w, state)
      _ -> :ok
    end

    {:noreply, %{state | waiters: remaining}}
  end

  @impl GenServer
  def handle_info(:ttl_expired, state) do
    {:stop, :normal, state}
  end

  ### endregion
  ##################################################

  ##################################################
  ### region Private Function

  defp ensure_storage(opts) do
    if Keyword.has_key?(opts, :storage) do
      opts
    else
      Keyword.put(opts, :storage, default_storage())
    end
  end

  defp default_storage do
    Application.get_env(:deep_blue, :durable_streams_storage, DurableStreams.Storage.ETS)
  end

  defp schedule_expiration(ttl, _expires_at) when is_integer(ttl) and ttl > 0 do
    Process.send_after(self(), :ttl_expired, ttl * 1000)
  end

  defp schedule_expiration(_ttl, %DateTime{} = expires_at) do
    now = DateTime.utc_now()
    diff_ms = DateTime.diff(expires_at, now, :millisecond)

    if diff_ms > 0 do
      Process.send_after(self(), :ttl_expired, diff_ms)
    else
      Process.send_after(self(), :ttl_expired, 0)
    end
  end

  defp schedule_expiration(_ttl, _expires_at), do: :ok

  defp reply_to_waiter({from, offset, timer_ref}, state) do
    Process.cancel_timer(timer_ref)
    result = state.storage.read(state.stream_id, offset)
    GenServer.reply(from, result)
  end

  defp reply_to_waiter({from, offset, timer_ref, :messages}, state) do
    Process.cancel_timer(timer_ref)
    result = state.storage.read_messages(state.stream_id, offset)
    GenServer.reply(from, result)
  end

  defp via_tuple(stream_id) do
    {:via, Registry, {DurableStreams.Registry, stream_id}}
  end

  ### endregion
  ##################################################
end
