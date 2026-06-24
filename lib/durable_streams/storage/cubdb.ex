defmodule DurableStreams.Storage.CubDB do
  @moduledoc """
  CubDB-based persistent storage backend for durable streams.

  Provides disk-backed, crash-safe storage using CubDB, an embedded
  key-value database with ACID transactions and MVCC.

  ## Key Structure

  - `{:meta, stream_id}` → `DurableStreams.Stream.t()` — Stream metadata
  - `{:data, stream_id, offset_int}` → `{binary(), non_neg_integer()}` — Message data + timestamp (ms)
  - `{:seq, stream_id}` → `String.t()` — Last sequence for ordering enforcement

  ## Configuration

      config :deep_blue, :durable_streams_storage, DurableStreams.Storage.CubDB
      config :deep_blue, DurableStreams.Storage.CubDB,
        data_dir: "priv/durable_streams_data"
  """

  @behaviour DurableStreams.Storage.Behaviour

  use GenServer

  alias DurableStreams.Offset

  @global_counter_key {:global_offset_counter}

  # ===========================================================================
  # Client API — Behaviour callbacks
  # ===========================================================================

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DurableStreams.Storage.Behaviour
  def create(stream_id, %DurableStreams.Stream{} = stream) do
    GenServer.call(__MODULE__, {:create, stream_id, stream})
  end

  @impl DurableStreams.Storage.Behaviour
  def get_metadata(stream_id) do
    GenServer.call(__MODULE__, {:get_metadata, stream_id})
  end

  @doc """
  Alias for `get_metadata/1`, used by retention worker.
  """
  @spec get(String.t()) :: {:ok, DurableStreams.Stream.t()} | {:error, :not_found}
  def get(stream_id), do: get_metadata(stream_id)

  @impl DurableStreams.Storage.Behaviour
  def append(stream_id, data, seq \\ nil) when is_binary(data) do
    GenServer.call(__MODULE__, {:append, stream_id, data, seq})
  end

  @impl DurableStreams.Storage.Behaviour
  def read(stream_id, from_offset) do
    GenServer.call(__MODULE__, {:read, stream_id, from_offset})
  end

  @impl DurableStreams.Storage.Behaviour
  def close(stream_id) do
    GenServer.call(__MODULE__, {:close, stream_id})
  end

  @impl DurableStreams.Storage.Behaviour
  def delete(stream_id) do
    GenServer.call(__MODULE__, {:delete, stream_id})
  end

  @impl DurableStreams.Storage.Behaviour
  def current_offset(stream_id) do
    GenServer.call(__MODULE__, {:current_offset, stream_id})
  end

  @impl DurableStreams.Storage.Behaviour
  def read_messages(stream_id, from_offset) do
    GenServer.call(__MODULE__, {:read_messages, stream_id, from_offset})
  end

  # ===========================================================================
  # Client API — Retention helpers (mirror ETS module interface)
  # ===========================================================================

  @doc """
  Returns the timestamp of the first (earliest) message in the stream.
  """
  @spec get_first_message_timestamp(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_first_message_timestamp(stream_id) do
    GenServer.call(__MODULE__, {:get_first_message_timestamp, stream_id})
  end

  @doc """
  Finds the offset of the first message with timestamp >= cutoff.
  Returns nil if no such message exists.
  """
  @spec find_offset_after_timestamp(String.t(), non_neg_integer()) :: String.t() | nil
  def find_offset_after_timestamp(stream_id, cutoff_ms) do
    GenServer.call(__MODULE__, {:find_offset_after_timestamp, stream_id, cutoff_ms})
  end

  @doc """
  Finds the offset after skipping n messages from the beginning.
  Used for max_messages retention.
  """
  @spec find_offset_after_n_messages(String.t(), non_neg_integer()) :: String.t() | nil
  def find_offset_after_n_messages(stream_id, n) do
    GenServer.call(__MODULE__, {:find_offset_after_n_messages, stream_id, n})
  end

  @doc """
  Finds the offset after removing at least target_bytes from the beginning.
  Used for max_bytes retention.
  """
  @spec find_offset_after_n_bytes(String.t(), non_neg_integer()) :: String.t() | nil
  def find_offset_after_n_bytes(stream_id, target_bytes) do
    GenServer.call(__MODULE__, {:find_offset_after_n_bytes, stream_id, target_bytes})
  end

  @doc """
  Deletes all messages before the given offset.
  Returns {:ok, deleted_count, deleted_bytes} on success.
  """
  @spec delete_messages_before(String.t(), String.t()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | {:error, term()}
  def delete_messages_before(stream_id, new_earliest_offset) do
    GenServer.call(__MODULE__, {:delete_messages_before, stream_id, new_earliest_offset})
  end

  @doc """
  Updates stream metadata after compaction.
  """
  @spec update_after_compaction(String.t(), String.t(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, term()}
  def update_after_compaction(stream_id, new_earliest, deleted_count, deleted_bytes) do
    GenServer.call(
      __MODULE__,
      {:update_after_compaction, stream_id, new_earliest, deleted_count, deleted_bytes}
    )
  end

  @doc """
  Lists all streams that have a retention policy configured.
  """
  @spec list_streams_with_retention() :: [DurableStreams.Stream.t()]
  def list_streams_with_retention do
    GenServer.call(__MODULE__, :list_streams_with_retention)
  end

  # ===========================================================================
  # GenServer callbacks
  # ===========================================================================

  @impl GenServer
  def init(opts) do
    data_dir = Keyword.get(opts, :data_dir, default_data_dir())
    File.mkdir_p!(data_dir)

    case CubDB.start_link(data_dir: data_dir) do
      {:ok, db} ->
        # Initialize the global offset counter if it doesn't exist yet.
        # Use system_time as the base so new offsets are always larger than
        # any previously generated offsets (erlang:unique_integer resets on restart).
        init_offset_counter(db)
        {:ok, %{db: db}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:create, stream_id, stream}, _from, %{db: db} = state) do
    result =
      CubDB.transaction(db, fn tx ->
        case CubDB.Tx.get(tx, {:meta, stream_id}) do
          nil ->
            tx = CubDB.Tx.put(tx, {:meta, stream_id}, stream)
            {:commit, tx, :ok}

          _ ->
            {:commit, tx, {:error, :already_exists}}
        end
      end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_metadata, stream_id}, _from, %{db: db} = state) do
    result =
      case CubDB.get(db, {:meta, stream_id}) do
        nil -> {:error, :not_found}
        stream -> {:ok, stream}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:append, stream_id, data, seq}, _from, %{db: db} = state) do
    timestamp = System.system_time(:millisecond)

    result =
      CubDB.transaction(db, fn tx ->
        case CubDB.Tx.get(tx, {:meta, stream_id}) do
          nil ->
            {:commit, tx, {:error, :not_found}}

          %DurableStreams.Stream{closed: true} ->
            {:commit, tx, {:error, :closed}}

          stream ->
            case check_seq_in_tx(tx, stream_id, seq) do
              {:error, _} = err ->
                {:commit, tx, err}

              :ok ->
                # Atomically read-and-increment the global offset counter.
                # This ensures offsets are monotonic across restarts.
                offset_int = CubDB.Tx.get(tx, @global_counter_key) || 0
                offset_int = offset_int + 1
                tx = CubDB.Tx.put(tx, @global_counter_key, offset_int)

                offset_str = int_to_offset(offset_int)

                tx = CubDB.Tx.put(tx, {:data, stream_id, offset_int}, {data, timestamp})
                tx = if seq, do: CubDB.Tx.put(tx, {:seq, stream_id}, seq), else: tx

                updated = %DurableStreams.Stream{
                  stream
                  | message_count: stream.message_count + 1,
                    total_bytes: stream.total_bytes + byte_size(data),
                    current_offset: offset_str,
                    earliest_offset: stream.earliest_offset || offset_str
                }

                tx = CubDB.Tx.put(tx, {:meta, stream_id}, updated)
                {:commit, tx, {:ok, offset_str}}
            end
        end
      end)

    # Broadcast OUTSIDE transaction (side effect)
    case result do
      {:ok, offset_str} ->
        Phoenix.PubSub.broadcast(
          DurableStreams.PubSub,
          "stream:#{stream_id}",
          {:stream_append, stream_id, offset_str}
        )

      _ ->
        :ok
    end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:read, stream_id, from_offset}, _from, %{db: db} = state) do
    result = read_internal(db, stream_id, from_offset, :binary)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:read_messages, stream_id, from_offset}, _from, %{db: db} = state) do
    result = read_internal(db, stream_id, from_offset, :messages)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:close, stream_id}, _from, %{db: db} = state) do
    result =
      CubDB.transaction(db, fn tx ->
        case CubDB.Tx.get(tx, {:meta, stream_id}) do
          nil ->
            {:commit, tx, {:error, :not_found}}

          stream ->
            tx =
              CubDB.Tx.put(tx, {:meta, stream_id}, %DurableStreams.Stream{stream | closed: true})

            {:commit, tx, :ok}
        end
      end)

    case result do
      :ok ->
        Phoenix.PubSub.broadcast(
          DurableStreams.PubSub,
          "stream:#{stream_id}",
          {:stream_closed, stream_id}
        )

      _ ->
        :ok
    end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete, stream_id}, _from, %{db: db} = state) do
    result =
      case CubDB.get(db, {:meta, stream_id}) do
        nil ->
          {:error, :not_found}

        _stream ->
          # Delete all data entries for this stream
          delete_all_stream_data(db, stream_id)

          # Delete metadata, seq, and streams index
          CubDB.transaction(db, fn tx ->
            tx = CubDB.Tx.delete(tx, {:meta, stream_id})
            tx = CubDB.Tx.delete(tx, {:seq, stream_id})
            {:commit, tx, :ok}
          end)
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:current_offset, stream_id}, _from, %{db: db} = state) do
    result =
      case CubDB.get(db, {:meta, stream_id}) do
        nil ->
          {:error, :not_found}

        %DurableStreams.Stream{current_offset: nil} ->
          {:ok, Offset.start()}

        %DurableStreams.Stream{current_offset: offset} ->
          {:ok, offset}
      end

    {:reply, result, state}
  end

  # ===========================================================================
  # Retention-related handle_call implementations
  # ===========================================================================

  @impl GenServer
  def handle_call({:get_first_message_timestamp, stream_id}, _from, %{db: db} = state) do
    result =
      case CubDB.get(db, {:meta, stream_id}) do
        nil ->
          {:error, :not_found}

        %DurableStreams.Stream{earliest_offset: nil} ->
          {:error, :no_messages}

        %DurableStreams.Stream{earliest_offset: offset} ->
          offset_int = Offset.to_integer(offset)

          case CubDB.get(db, {:data, stream_id, offset_int}) do
            {_data, timestamp} -> {:ok, timestamp}
            nil -> {:error, :no_messages}
          end
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:find_offset_after_timestamp, stream_id, cutoff_ms}, _from, %{db: db} = state) do
    result =
      reduce_stream(db, stream_id, nil, fn {_key, _data, ts, offset_int}, _acc ->
        if ts >= cutoff_ms, do: {:halt, int_to_offset(offset_int)}, else: {:cont, nil}
      end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:find_offset_after_n_messages, stream_id, n}, _from, %{db: db} = state) do
    result =
      case reduce_stream(db, stream_id, 0, fn {_key, _data, _ts, offset_int}, idx ->
             if idx == n, do: {:halt, {:found, int_to_offset(offset_int)}}, else: {:cont, idx + 1}
           end) do
        {:found, offset} -> offset
        _ -> nil
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:find_offset_after_n_bytes, stream_id, target_bytes}, _from, %{db: db} = state) do
    result =
      case reduce_stream(db, stream_id, 0, fn {_key, data, _ts, offset_int}, bytes ->
             new_bytes = bytes + byte_size(data)

             if new_bytes >= target_bytes,
               do: {:halt, {:found, int_to_offset(offset_int)}},
               else: {:cont, new_bytes}
           end) do
        {:found, offset} -> offset
        _ -> nil
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(
        {:delete_messages_before, stream_id, new_earliest_offset},
        _from,
        %{db: db} = state
      ) do
    new_earliest_int = Offset.to_integer(new_earliest_offset)

    {deleted_count, deleted_bytes} =
      delete_stream_while(db, stream_id, fn {_key, _data, _ts, offset_int} ->
        offset_int < new_earliest_int
      end)

    {:reply, {:ok, deleted_count, deleted_bytes}, state}
  end

  @impl GenServer
  def handle_call(
        {:update_after_compaction, stream_id, new_earliest, deleted_count, deleted_bytes},
        _from,
        %{db: db} = state
      ) do
    result =
      CubDB.transaction(db, fn tx ->
        case CubDB.Tx.get(tx, {:meta, stream_id}) do
          nil ->
            {:commit, tx, {:error, :not_found}}

          stream ->
            updated = %DurableStreams.Stream{
              stream
              | earliest_offset: new_earliest,
                message_count: max(0, stream.message_count - deleted_count),
                total_bytes: max(0, stream.total_bytes - deleted_bytes)
            }

            tx = CubDB.Tx.put(tx, {:meta, stream_id}, updated)
            {:commit, tx, :ok}
        end
      end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:list_streams_with_retention, _from, %{db: db} = state) do
    streams =
      CubDB.select(db, min_key: {:meta, ""})
      |> Stream.take_while(&meta_key?/1)
      |> Stream.map(fn {_key, stream} -> stream end)
      |> Stream.filter(fn %DurableStreams.Stream{retention_policy: policy} ->
        not is_nil(policy)
      end)
      |> Enum.to_list()

    {:reply, streams, state}
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  # Shared implementation for read/2 and read_messages/2
  # format: :binary returns concatenated data, :messages returns list of message maps
  defp read_internal(db, stream_id, from_offset, format) do
    case CubDB.get(db, {:meta, stream_id}) do
      nil ->
        {:error, :not_found}

      stream ->
        chunks = get_chunks_after(db, stream_id, from_offset)
        current_off = stream.current_offset || Offset.start()

        case chunks do
          [] ->
            empty_result(current_off, stream.closed, format)

          _ ->
            {_key, _data, _ts, last_offset_int} = List.last(chunks)
            last_offset = int_to_offset(last_offset_int)
            chunks_result(chunks, last_offset, stream.closed, format)
        end
    end
  end

  defp empty_result(offset, closed, :binary) do
    {:ok, %{data: <<>>, offset: offset, has_more: false, closed: closed}}
  end

  defp empty_result(offset, closed, :messages) do
    {:ok, %{messages: [], offset: offset, has_more: false, closed: closed}}
  end

  defp chunks_result(chunks, last_offset, closed, :binary) do
    data = chunks |> Enum.map(fn {_key, d, _ts, _off} -> d end) |> IO.iodata_to_binary()
    {:ok, %{data: data, offset: last_offset, has_more: false, closed: closed}}
  end

  defp chunks_result(chunks, last_offset, closed, :messages) do
    messages =
      Enum.map(chunks, fn {_key, data, _ts, offset_int} ->
        %{data: data, offset: int_to_offset(offset_int)}
      end)

    {:ok, %{messages: messages, offset: last_offset, has_more: false, closed: closed}}
  end

  # Convert offset integer back to hex string format
  defp int_to_offset(offset_int) do
    :io_lib.format("~16.16.0b", [offset_int]) |> IO.iodata_to_binary()
  end

  # Returns chunks after the given offset (exclusive)
  defp get_chunks_after(db, stream_id, from_offset) do
    from_int =
      if Offset.start?(from_offset) do
        -1
      else
        Offset.to_integer(from_offset) || -1
      end

    stream_data(db, stream_id)
    |> Stream.filter(fn {_key, _data, _ts, offset_int} -> offset_int > from_int end)
    |> Enum.to_list()
  end

  # Lazily select all data entries for a stream, returning {key, data, ts, offset_int} tuples.
  # Stops iteration when hitting any non-:data key (e.g., {:global_offset_counter}, {:meta, ...}).
  defp stream_data(db, stream_id) do
    CubDB.select(db, min_key: {:data, stream_id, 0})
    |> Stream.take_while(&data_key_for_stream?(&1, stream_id))
    |> Stream.map(fn {{:data, _sid, offset_int}, {data, ts}} ->
      {{:data, stream_id, offset_int}, data, ts, offset_int}
    end)
  end

  defp data_key_for_stream?({{:data, sid, _}, _}, stream_id), do: sid == stream_id
  defp data_key_for_stream?(_, _), do: false

  defp meta_key?({{:meta, _}, _}), do: true
  defp meta_key?(_), do: false

  # Iterate from beginning of stream, reducing with a callback
  # Callback receives {key, data, ts, offset_int}, acc → {:cont, new_acc} | {:halt, result}
  defp reduce_stream(db, stream_id, acc, fun) do
    stream_data(db, stream_id)
    |> Enum.reduce_while(acc, fn {key, data, ts, offset_int}, acc ->
      fun.({key, data, ts, offset_int}, acc)
    end)
  end

  # Delete all data entries for a stream
  defp delete_all_stream_data(db, stream_id) do
    delete_stream_while(db, stream_id, fn _ -> true end)
  end

  # Delete data entries while condition holds, returns {deleted_count, deleted_bytes}
  defp delete_stream_while(db, stream_id, fun) do
    # Collect keys to delete first, then delete them in a transaction
    keys_to_delete =
      stream_data(db, stream_id)
      |> Enum.reduce_while({0, 0, []}, fn {key, data, _ts, offset_int}, {count, bytes, keys} ->
        if fun.({key, data, _ts, offset_int}) do
          {:cont, {count + 1, bytes + byte_size(data), [{:data, stream_id, offset_int} | keys]}}
        else
          {:halt, {count, bytes, keys}}
        end
      end)

    case keys_to_delete do
      {0, 0, []} ->
        {0, 0}

      {count, bytes, keys} ->
        # Delete in batches using delete_multi for efficiency
        Enum.each(keys, fn key ->
          CubDB.delete(db, key)
        end)

        {count, bytes}
    end
  end

  # Check sequence ordering within a transaction
  defp check_seq_in_tx(_tx, _stream_id, nil), do: :ok

  defp check_seq_in_tx(tx, stream_id, new_seq) do
    case CubDB.Tx.get(tx, {:seq, stream_id}) do
      nil ->
        :ok

      last_seq ->
        # Seq must be lexicographically greater than last_seq
        # And must not be equal (duplicate rejection)
        if new_seq > last_seq do
          :ok
        else
          {:error, :seq_conflict}
        end
    end
  end

  # Initialize the global offset counter if it doesn't exist.
  # Uses system_time (milliseconds) as the base so new offsets are always
  # larger than any previously generated by erlang:unique_integer (which resets on restart).
  defp init_offset_counter(db) do
    case CubDB.get(db, @global_counter_key) do
      nil ->
        CubDB.put(db, @global_counter_key, System.system_time(:millisecond))

      _ ->
        :ok
    end
  end

  defp default_data_dir do
    :deep_blue
    |> Application.app_dir("priv")
    |> Path.join("durable_streams_data")
  end
end
