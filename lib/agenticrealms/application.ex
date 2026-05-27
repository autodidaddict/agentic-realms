defmodule AgenticRealms.Application do
  # Feature 009 — pre-declare the atoms used as keys inside the
  # `behaviors` JSONB field of RoomCreated / NPCBlueprintCreated /
  # NPCClonedFromBlueprint events. The eventstore's JsonSerializer
  # deserializes event payloads with `Jason.decode!(..., keys: :atoms!)`,
  # which recursively atomizes ALL keys in the JSON — including the
  # nested behavior maps' keys. If these atoms aren't already known to
  # the BEAM at deserialize time, `binary_to_existing_atom/1` crashes
  # the notification publisher. Referencing them in a compile-time
  # module attribute guarantees they exist in the atom table.
  # Feature 011 adds :interval_ms (used by tick behaviors).
  @_behavior_atoms [:trigger, :actions, :type, :text, :interval_ms]
  def __behavior_atoms__, do: @_behavior_atoms

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AgenticRealmsWeb.Telemetry,
        AgenticRealms.Repo,
        {DNSCluster, query: Application.get_env(:agenticrealms, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: AgenticRealms.PubSub},
        AgenticRealmsWeb.Presence,
        # Supervises per-request natural-language intent-resolver tasks
        # (feature 005) so a slow or crashing Anthropic call cannot take
        # down the LiveView that spawned it.
        {Task.Supervisor, name: AgenticRealms.IntentResolverTaskSupervisor},
        # Feature 010 — cluster-wide registry + dynamic supervisor for the
        # per-(player, NPC) chat Conversation GenServers, plus a dedicated
        # Task.Supervisor for the LLM round-trips those Conversations spawn.
        AgenticRealms.World.NPCChat.Registry,
        AgenticRealms.World.NPCChat.Supervisor,
        AgenticRealms.World.NPCChat.TaskSupervisor,
        # Feature 011 — cluster-wide registry + dynamic supervisor for the
        # per-room tick Scheduler GenServers, plus a singleton Lifecycle
        # process that watches Phoenix.Presence + room events to detect
        # 0↔1 live-occupancy transitions and start/stop schedulers with
        # configurable grace periods.
        AgenticRealms.World.Ticks.Registry,
        AgenticRealms.World.Ticks.Supervisor,
        AgenticRealms.World.Ticks.Lifecycle
      ] ++
        commanded_children() ++
        [
          # Start to serve requests, typically the last entry
          AgenticRealmsWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AgenticRealms.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Commanded chain — the World.Application (Commanded.Application), the
  # event store adapter it brings up transitively, the read-model
  # projectors, and the broadcast/behavior event handlers.
  #
  # In :test the chain is started per-test via `start_supervised!/1` in
  # `AgenticRealms.DataCase.setup_commanded/0` so each test gets a fresh
  # in-memory event store + fresh subscription positions (issue #10).
  # Tests opt in with `@moduletag :commanded`.
  defp commanded_children do
    if Application.get_env(:agenticrealms, :start_commanded?, true) do
      [
        # AgenticRealms.EventStore is started transitively by World.Application
        # via the commanded_eventstore_adapter — listing it here causes a
        # double-start (:already_started).
        AgenticRealms.World.Application,
        AgenticRealms.World.Projections.WorldProjector,
        AgenticRealms.World.Projections.PlayerStateProjector,
        AgenticRealms.World.UIEventBroadcaster,
        AgenticRealms.World.Behaviors.Interpreter
      ]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AgenticRealmsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
