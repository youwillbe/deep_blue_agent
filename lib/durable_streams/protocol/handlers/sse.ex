defmodule DurableStreams.Protocol.Handlers.SSE do
  @moduledoc """
  Internal handler for GET requests with `live=sse` for Server-Sent Events.

  Streams data to the client as SSE events, with control events
  containing cursor and upToDate flags.

  ## SSE Event Types

  - `data` - Contains stream data with offset as the event ID
  - `control` - Contains cursor, nextOffset, and upToDate status

  ## Connection Lifecycle

  Per the Durable Streams protocol, SSE connections are closed after ~60 seconds
  to enable CDN collapsing. Clients should reconnect using the last received offset.

  This is an internal module used by `DurableStreams.Protocol.Plug`.
  """

  import Plug.Conn
  alias DurableStreams.{JSON, Offset, Stream, Server}

  # Per protocol: close SSE connections after ~60 seconds for CDN collapsing
  @connection_timeout_ms 60_000

  def call(conn) do
    stream_id = conn.path_params["stream_id"]
    offset = conn.params["offset"]

    # SSE requires offset parameter
    if is_nil(offset) or offset == "" do
      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(400, JSON.encode!(%{error: "Offset parameter required for SSE"}))
    else
      case Server.get_metadata(stream_id) do
        {:ok, meta} ->
          # Get client cursor for jitter handling - can be in header OR query param
          client_cursor =
            get_req_header(conn, "stream-cursor") |> List.first() || conn.params["cursor"]

          conn
          |> put_resp_header("content-type", "text/event-stream")
          |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
          |> put_resp_header("connection", "keep-alive")
          |> delete_resp_header("content-length")
          |> send_chunked(200)
          |> send_initial_state(stream_id, offset, meta, client_cursor)

        {:error, :not_found} ->
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(404, JSON.encode!(%{error: "Stream not found"}))
      end
    end
  end

  # Send initial state (existing data or immediate control for empty stream)
  # This ensures clients get an immediate response, not waiting for new data
  defp send_initial_state(conn, stream_id, offset, meta, client_cursor) do
    started_at = System.monotonic_time(:millisecond)

    if Stream.json_mode?(meta) do
      send_initial_json_state(conn, stream_id, offset, client_cursor, started_at)
    else
      send_initial_binary_state(conn, stream_id, offset, meta, client_cursor, started_at)
    end
  end

  defp send_initial_binary_state(conn, stream_id, offset, meta, client_cursor, started_at) do
    # Read without live mode - get current state immediately
    case Server.read(stream_id, offset, live: false) do
      {:ok, %{data: <<>>} = result} ->
        # Empty stream - send initial control event immediately, then wait for data
        case send_control_event(
               conn,
               result.offset,
               true,
               result.closed,
               stream_id,
               client_cursor
             ) do
          {:ok, conn} when result.closed -> conn
          {:ok, conn} -> stream_binary_loop(conn, stream_id, result.offset, meta, nil, started_at)
          {:error, _} -> conn
        end

      {:ok, result} ->
        # Has data - send it, then continue looping
        data = format_data(result.data, meta)
        event = build_data_event(data, result.offset)

        case chunk(conn, event) do
          {:ok, conn} ->
            case send_control_event(
                   conn,
                   result.offset,
                   !result.has_more,
                   result.closed,
                   stream_id,
                   client_cursor
                 ) do
              {:ok, conn} when result.closed ->
                conn

              {:ok, conn} ->
                stream_binary_loop(conn, stream_id, result.offset, meta, nil, started_at)

              {:error, _} ->
                conn
            end

          {:error, _} ->
            conn
        end

      {:error, _} ->
        conn
    end
  end

  defp send_initial_json_state(conn, stream_id, offset, client_cursor, started_at) do
    # Read without live mode - get current state immediately
    case Server.read_messages(stream_id, offset, live: false) do
      {:ok, %{messages: []} = result} ->
        # Empty stream - send initial control event immediately, then wait for data
        case send_control_event(
               conn,
               result.offset,
               true,
               result.closed,
               stream_id,
               client_cursor
             ) do
          {:ok, conn} when result.closed -> conn
          {:ok, conn} -> stream_json_loop(conn, stream_id, result.offset, nil, started_at)
          {:error, _} -> conn
        end

      {:ok, result} ->
        # Batch all messages into a single data event
        {last_offset, json_array} =
          Enum.reduce(result.messages, {offset, []}, fn msg, {_acc, items} ->
            item =
              case JSON.decode(msg.data) do
                {:ok, parsed} -> parsed
                {:error, _} -> msg.data
              end

            {msg.offset, [item | items]}
          end)

        json_data = JSON.encode!(Enum.reverse(json_array))
        event = build_data_event(json_data, last_offset)

        case chunk(conn, event) do
          {:ok, conn} ->
            case send_control_event(
                   conn,
                   last_offset,
                   !result.has_more,
                   result.closed,
                   stream_id,
                   client_cursor
                 ) do
              {:ok, conn} when result.closed -> conn
              {:ok, conn} -> stream_json_loop(conn, stream_id, last_offset, nil, started_at)
              {:error, _} -> conn
            end

          {:error, _} ->
            conn
        end

      {:error, _} ->
        conn
    end
  end

  defp stream_binary_loop(conn, stream_id, offset, meta, client_cursor, started_at) do
    # Check if connection timeout has been reached
    elapsed = System.monotonic_time(:millisecond) - started_at

    if elapsed >= @connection_timeout_ms do
      # Close connection after ~60 seconds for CDN collapsing
      conn
    else
      case Server.read(stream_id, offset, live: true, timeout: 5_000) do
        {:ok, %{data: <<>>, closed: true} = result} ->
          send_control_event(conn, result.offset, true, true, stream_id, client_cursor)
          conn

        {:ok, %{data: <<>>} = result} ->
          stream_binary_loop(conn, stream_id, result.offset, meta, nil, started_at)

        {:ok, result} ->
          # Send data event
          data = format_data(result.data, meta)
          event = build_data_event(data, result.offset)

          # Check fresh closed state: the stream may have been closed between
          # the live read and now (e.g. close right after append)
          fresh_closed = !result.closed and fresh_stream_closed?(stream_id)
          closed? = result.closed or fresh_closed

          case chunk(conn, event) do
            {:ok, conn} ->
              # Send control event after data
              case send_control_event(
                     conn,
                     result.offset,
                     !result.has_more or fresh_closed,
                     closed?,
                     stream_id,
                     client_cursor
                   ) do
                {:ok, conn} when closed? ->
                  conn

                {:ok, conn} ->
                  stream_binary_loop(conn, stream_id, result.offset, meta, nil, started_at)

                {:error, _} ->
                  conn
              end

            {:error, _} ->
              conn
          end

        {:error, _} ->
          conn
      end
    end
  end

  defp stream_json_loop(conn, stream_id, offset, client_cursor, started_at) do
    # Check if connection timeout has been reached
    elapsed = System.monotonic_time(:millisecond) - started_at

    if elapsed >= @connection_timeout_ms do
      # Close connection after ~60 seconds for CDN collapsing
      conn
    else
      case Server.read_messages(stream_id, offset, live: true, timeout: 5_000) do
        {:ok, %{messages: [], closed: true} = result} ->
          send_control_event(conn, result.offset, true, true, stream_id, client_cursor)
          conn

        {:ok, %{messages: []} = result} ->
          stream_json_loop(conn, stream_id, result.offset, nil, started_at)

        {:ok, result} ->
          # Batch all messages into a single data event
          {last_offset, json_array} =
            Enum.reduce(result.messages, {offset, []}, fn msg, {_acc, items} ->
              item =
                case JSON.decode(msg.data) do
                  {:ok, parsed} -> parsed
                  {:error, _} -> msg.data
                end

              {msg.offset, [item | items]}
            end)

          json_data = JSON.encode!(Enum.reverse(json_array))
          event = build_data_event(json_data, last_offset)

          # Check fresh closed state: the stream may have been closed between
          # the live read and now (e.g. close right after append)
          fresh_closed = !result.closed and fresh_stream_closed?(stream_id)
          closed? = result.closed or fresh_closed

          case chunk(conn, event) do
            {:ok, conn} ->
              case send_control_event(
                     conn,
                     last_offset,
                     !result.has_more or fresh_closed,
                     closed?,
                     stream_id,
                     client_cursor
                   ) do
                {:ok, conn} when closed? -> conn
                {:ok, conn} -> stream_json_loop(conn, stream_id, last_offset, nil, started_at)
                {:error, _} -> conn
              end

            {:error, _} ->
              conn
          end

        {:error, _} ->
          conn
      end
    end
  end

  defp fresh_stream_closed?(stream_id) do
    case Server.get_metadata(stream_id) do
      {:ok, %{closed: true}} -> true
      _ -> false
    end
  end

  defp build_data_event(data, offset) do
    # Handle newlines in data by prefixing each line with "data: "
    lines = Enum.map_join(String.split(data, "\n"), "\n", &"data: #{&1}")

    """
    event: data
    #{lines}
    id: #{offset}\n
    """
  end

  defp send_control_event(conn, offset, up_to_date, closed, _stream_id, client_cursor) do
    event = build_control_event(client_cursor, offset, up_to_date, closed)

    chunk(conn, event)
  end

  defp build_control_event(client_cursor, offset, up_to_date, closed) do
    cursor = generate_cursor_with_jitter(nil, client_cursor)
    actual_offset = if Offset.start?(offset), do: Offset.zero(), else: offset
    control = control_event_map(cursor, actual_offset, up_to_date, closed)

    """
    event: control
    data: #{JSON.encode!(control)}\n
    """
  end

  defp control_event_map(cursor, offset, up_to_date, true = _streamClosed) do
    %{
      "streamCursor" => cursor,
      "streamNextOffset" => offset,
      "upToDate" => up_to_date,
      "streamClosed" => true
    }
  end

  defp control_event_map(cursor, offset, up_to_date, false = _streamClosed) do
    %{
      "streamCursor" => cursor,
      "streamNextOffset" => offset,
      "upToDate" => up_to_date
    }
  end

  defp format_data(data, meta) when is_binary(data) do
    # For text/plain, just use the data as-is
    # For other types, the client should decode appropriately
    if String.starts_with?(meta.content_type, "text/") do
      data
    else
      Base.encode64(data)
    end
  end

  # Cursor is just a millisecond timestamp (numeric string)
  defp generate_cursor do
    Integer.to_string(System.system_time(:millisecond))
  end

  defp generate_cursor_with_jitter(_stream_id, nil) do
    generate_cursor()
  end

  defp generate_cursor_with_jitter(_stream_id, client_cursor) do
    # Parse the client cursor (now just a numeric timestamp)
    case Integer.parse(client_cursor) do
      {cursor_timestamp, ""} ->
        now = System.system_time(:millisecond)
        # If client cursor is recent (within 1 second), increment timestamp to ensure uniqueness
        if now - cursor_timestamp < 1000 do
          # Add jitter - use a timestamp slightly after the client's
          Integer.to_string(cursor_timestamp + 1)
        else
          generate_cursor()
        end

      _ ->
        generate_cursor()
    end
  end
end
