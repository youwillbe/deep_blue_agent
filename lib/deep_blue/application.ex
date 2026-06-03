defmodule DeepBlue.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    snapshot = LLMDB.Store.snapshot()

    {:ok, updated_snapshot} =
      LLMDB.Runtime.apply(snapshot, %{
        filter: %{
          allow: %{ctyun: ["*"], zhipu: ["*"]},
          deny: %{}
        }
      })

    LLMDB.Store.put!(updated_snapshot, [])

    children = [
      DeepBlueWeb.Telemetry,
      DeepBlue.Repo,
      {DNSCluster, query: Application.get_env(:deep_blue, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DeepBlue.PubSub},
      Supervisor.child_spec({Phoenix.PubSub, name: DurableStreams.PubSub}, id: DurableStreams.PubSub),
      {Registry, keys: :unique, name: DurableStreams.Registry},
      {DynamicSupervisor, name: DurableStreams.StreamSupervisor, strategy: :one_for_one},
      DurableStreams.Storage.ETS,
      DeepBlue.Jido,
      DeepBlueWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: DeepBlue.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DeepBlueWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
