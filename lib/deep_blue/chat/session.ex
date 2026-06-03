defmodule DeepBlue.Chat.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false, read_after_writes: true}
  schema "chat_sessions" do
    field :title, :string
    field :agent_config, :map

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:title, :agent_config])
  end
end
