defmodule DurableStreams.Storage.Behaviour do
  @moduledoc """
  Behaviour defining the storage interface for durable streams.
  """

  alias DurableStreams.{Offset, Stream}

  @type stream_id :: String.t()
  @type offset :: Offset.t()

  @type read_result :: %{
          data: binary(),
          offset: offset(),
          has_more: boolean(),
          closed: boolean()
        }

  @callback create(stream_id, Stream.t()) :: :ok | {:error, :already_exists}

  @callback get_metadata(stream_id) :: {:ok, Stream.t()} | {:error, :not_found}

  @callback append(stream_id, binary(), String.t() | nil) ::
              {:ok, offset} | {:error, :not_found | :closed | :seq_conflict}

  @callback read(stream_id, offset) :: {:ok, read_result} | {:error, :not_found}

  @callback close(stream_id) :: :ok | {:error, :not_found}

  @callback delete(stream_id) :: :ok | {:error, :not_found}

  @callback current_offset(stream_id) :: {:ok, offset} | {:error, :not_found}

  @type message :: %{data: binary(), offset: offset()}
  @type read_messages_result :: %{
          messages: [message()],
          offset: offset(),
          has_more: boolean(),
          closed: boolean()
        }

  @callback read_messages(stream_id, offset) :: {:ok, read_messages_result} | {:error, :not_found}
end
