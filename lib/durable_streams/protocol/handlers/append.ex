defmodule DurableStreams.Protocol.Handlers.Append do
  @moduledoc """
  Internal handler for POST requests to append data to a stream.

  In JSON mode:
  - Array POSTs are flattened one level (each element stored separately)
  - Non-array POSTs store the entire JSON as one message
  - Empty arrays are rejected with 400

  This is an internal module used by `DurableStreams.Protocol.Plug`.
  """

  import Plug.Conn
  alias DurableStreams.{JSON, Stream, Server}

  def call(conn) do
    stream_id = conn.path_params["stream_id"]
    content_type = get_req_header(conn, "content-type") |> List.first()
    seq = get_req_header(conn, "stream-seq") |> List.first()
    close? = get_req_header(conn, "stream-closed") |> List.first() == "true"

    # Close-only request: Stream-Closed: true with empty body
    if close? do
      body = read_body_from_conn(conn)

      if byte_size(body) == 0 do
        handle_close(conn, stream_id)
      else
        # Append + close
        do_append_then_close(conn, stream_id, body, content_type, seq)
      end
    else
      # Normal append - Content-Type is required
      if is_nil(content_type) do
        send_error(conn, 400, "Content-Type header is required")
      else
        case Server.get_metadata(stream_id) do
          {:ok, meta} ->
            if Stream.content_type_matches?(meta.content_type, content_type) do
              body = read_body_from_conn(conn)

              if byte_size(body) == 0 do
                send_error(conn, 400, "Request body cannot be empty")
              else
                if Stream.json_mode?(meta) do
                  handle_json_append(conn, stream_id, body, seq)
                else
                  handle_binary_append(conn, stream_id, body, seq)
                end
              end
            else
              send_error(conn, 409, "Content-Type mismatch")
            end

          {:error, :not_found} ->
            send_error(conn, 404, "Stream not found")
        end
      end
    end
  end

  defp handle_close(conn, stream_id) do
    case Server.close(stream_id) do
      :ok ->
        conn
        |> put_resp_header("stream-closed", "true")
        |> send_resp(204, "")

      {:error, :not_found} ->
        send_error(conn, 404, "Stream not found")
    end
  end

  defp do_append_then_close(conn, stream_id, body, content_type, seq) do
    # First get metadata for content type check and json mode
    case Server.get_metadata(stream_id) do
      {:ok, meta} ->
        if content_type && !Stream.content_type_matches?(meta.content_type, content_type) do
          send_error(conn, 409, "Content-Type mismatch")
        else
          result =
            if Stream.json_mode?(meta) do
              do_json_append(stream_id, body, seq)
            else
              Server.append(stream_id, body, seq: seq)
            end

          case result do
            {:ok, offset} ->
              Server.close(stream_id)

              conn
              |> put_resp_header("stream-closed", "true")
              |> send_append_response(offset)

            {:error, :not_found} ->
              send_error(conn, 404, "Stream not found")

            {:error, :closed} ->
              send_error(conn, 409, "Stream is closed")

            {:error, :seq_conflict} ->
              send_error(conn, 409, "Sequence ordering violation")
          end
        end

      {:error, :not_found} ->
        send_error(conn, 404, "Stream not found")
    end
  end

  defp do_json_append(stream_id, body, seq) do
    case JSON.decode(body) do
      {:ok, items} when is_list(items) ->
        if items == [] do
          {:error, :empty_array}
        else
          append_multiple_result(stream_id, items, seq)
        end

      {:ok, _single} ->
        Server.append(stream_id, body, seq: seq)
    end
  end

  defp append_multiple_result(stream_id, items, seq) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, nil}, fn {item, index}, _acc ->
      encoded = JSON.encode!(item)
      item_seq = if seq, do: increment_seq(seq, index), else: nil

      case Server.append(stream_id, encoded, seq: item_seq) do
        {:ok, offset} -> {:cont, {:ok, offset}}
        error -> {:halt, error}
      end
    end)
  end

  defp read_body_from_conn(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        case safe_read_body(conn) do
          {:ok, body, _conn} -> body
          _ -> ""
        end

      params when is_map(params) and map_size(params) > 0 ->
        JSON.encode!(params)

      _ ->
        ""
    end
  end

  defp handle_binary_append(conn, stream_id, body, seq) do
    case Server.append(stream_id, body, seq: seq) do
      {:ok, offset} ->
        send_append_response(conn, offset)

      {:error, :not_found} ->
        send_error(conn, 404, "Stream not found")

      {:error, :closed} ->
        send_error(conn, 409, "Stream is closed")

      {:error, :seq_conflict} ->
        send_error(conn, 409, "Sequence ordering violation")
    end
  end

  defp handle_json_append(conn, stream_id, body, seq) do
    case JSON.decode(body) do
      {:ok, items} when is_list(items) ->
        # Reject empty arrays
        if items == [] do
          send_error(conn, 400, "Empty JSON array not allowed")
        else
          # Flatten one level: store each array element as a separate message
          append_multiple(conn, stream_id, items, seq)
        end

      {:ok, _single} ->
        # Non-array: store as single message
        do_append(conn, stream_id, body, seq)

      {:error, _} ->
        send_error(conn, 400, "Invalid JSON")
    end
  end

  defp append_multiple(conn, stream_id, items, seq) do
    # For multiple items, we increment the seq for each
    results =
      items
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, nil}, fn {item, index}, _acc ->
        encoded = JSON.encode!(item)
        item_seq = if seq, do: increment_seq(seq, index), else: nil

        case Server.append(stream_id, encoded, seq: item_seq) do
          {:ok, offset} -> {:cont, {:ok, offset}}
          error -> {:halt, error}
        end
      end)

    case results do
      {:ok, last_offset} when last_offset != nil ->
        send_append_response(conn, last_offset)

      {:error, :closed} ->
        send_error(conn, 409, "Stream is closed")

      {:error, :not_found} ->
        send_error(conn, 404, "Stream not found")

      {:error, :seq_conflict} ->
        send_error(conn, 409, "Sequence ordering violation")
    end
  end

  defp do_append(conn, stream_id, body, seq) do
    case Server.append(stream_id, body, seq: seq) do
      {:ok, offset} ->
        send_append_response(conn, offset)

      {:error, :not_found} ->
        send_error(conn, 404, "Stream not found")

      {:error, :closed} ->
        send_error(conn, 409, "Stream is closed")

      {:error, :seq_conflict} ->
        send_error(conn, 409, "Sequence ordering violation")
    end
  end

  # Increment a string seq value by appending the index
  defp increment_seq(base_seq, 0), do: base_seq
  defp increment_seq(base_seq, index), do: "#{base_seq}.#{index}"

  defp send_append_response(conn, offset) do
    conn
    |> put_resp_header("stream-next-offset", offset)
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, JSON.encode!(%{offset: offset}))
  end

  # Safely read body, catching errors from large payloads
  defp safe_read_body(conn) do
    # Read body with a generous limit (100MB)
    case read_body(conn, length: 100_000_000, read_length: 1_000_000) do
      {:ok, body, conn} ->
        {:ok, body, conn}

      {:more, _partial, conn} ->
        # Body too large - read and discard remaining then return error
        drain_body(conn)
        {:error, :too_large, conn}

      {:error, _reason} ->
        {:error, :too_large, conn}
    end
  rescue
    _ -> {:error, :too_large, conn}
  end

  defp drain_body(conn) do
    case read_body(conn, length: 100_000_000, read_length: 1_000_000) do
      {:more, _, conn} -> drain_body(conn)
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  defp send_error(conn, status, message) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(status, JSON.encode!(%{error: message}))
  end
end
