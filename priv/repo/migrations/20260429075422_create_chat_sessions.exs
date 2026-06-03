defmodule DeepBlue.Repo.Migrations.CreateChatSessions do
  use Ecto.Migration

  def change do
    create table(:chat_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("uuidv7()")
      add :title, :string
      add :agent_config, :map

      timestamps(type: :utc_datetime)
    end
  end
end
