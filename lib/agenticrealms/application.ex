defmodule AgenticRealms.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AgenticRealmsWeb.Telemetry,
      AgenticRealms.Repo,
      {DNSCluster, query: Application.get_env(:agenticrealms, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AgenticRealms.PubSub},
      AgenticRealmsWeb.Presence,
      # AgenticRealms.EventStore is started transitively by World.Application
      # via the commanded_eventstore_adapter — listing it here causes a
      # double-start (:already_started).
      AgenticRealms.World.Application,
      AgenticRealms.World.Projections.WorldProjector,
      AgenticRealms.World.Projections.PlayerStateProjector,
      AgenticRealms.World.UIEventBroadcaster,
      # Start to serve requests, typically the last entry
      AgenticRealmsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AgenticRealms.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AgenticRealmsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
