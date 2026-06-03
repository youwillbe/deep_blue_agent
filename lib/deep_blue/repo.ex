defmodule DeepBlue.Repo do
  use Ecto.Repo,
    otp_app: :deep_blue,
    adapter: Ecto.Adapters.Postgres
end
