defmodule DurableStreams.Protocol.Plug do
  @moduledoc """
  Plug router implementing the Durable Streams HTTP protocol.

  ## Phoenix Integration

      forward "/v1/stream", DurableStreams.Protocol.Plug

  ## Standalone Usage

      # In your application.ex
      children = [
        # ... other children
        {Plug.Cowboy, scheme: :http, plug: DurableStreams.Protocol.Plug, options: [port: 4000]}
      ]

  ## HTTP API

  | Method | Path | Purpose |
  |--------|------|---------|
  | `PUT` | `/:stream_id` | Create stream |
  | `POST` | `/:stream_id` | Append data |
  | `GET` | `/:stream_id` | Read from offset |
  | `DELETE` | `/:stream_id` | Delete stream |
  | `HEAD` | `/:stream_id` | Get metadata |
  """

  use Plug.Router

  alias DurableStreams.Protocol.Handlers

  plug(:cors)
  plug(Plug.Logger)
  plug(:match)
  plug(:fetch_query_params)
  plug(:dispatch)

  options _ do
    send_resp(conn, 204, "")
  end

  put "/:stream_id" do
    Handlers.Create.call(conn)
  end

  post "/:stream_id" do
    Handlers.Append.call(conn)
  end

  get "/:stream_id" do
    case conn.params["live"] do
      "sse" -> Handlers.SSE.call(conn)
      _ -> Handlers.Read.call(conn)
    end
  end

  delete "/:stream_id" do
    Handlers.Delete.call(conn)
  end

  head "/:stream_id" do
    Handlers.Head.call(conn)
  end

  match _ do
    conn
    |> send_resp(404, "Not Found")
  end

  defp cors(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, HEAD, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "*")
    |> put_resp_header(
      "access-control-expose-headers",
      "stream-next-offset, stream-up-to-date, stream-cursor, stream-closed, stream-earliest-offset, etag"
    )
  end
end
