defmodule AgenticRealms.Application do
  @_behavior_atoms [:trigger, :actions, :type, :text, :interval_ms]
  @spec __behavior_atoms__() :: [atom()]
  def __behavior_atoms__, do: @_behavior_atoms

  @_quest_atoms [
    :slug,
    :title,
    :narrative,
    :criteria,
    :reward,
    :name,
    :quest_tag,
    :target_count,
    :spawn_room_ids,
    :description,
    :tag,
    :item_name,
    :item_short_description,
    :item_long_description
  ]
  @spec __quest_atoms__() :: [atom()]
  def __quest_atoms__, do: @_quest_atoms

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
        {Task.Supervisor, name: AgenticRealms.IntentResolverTaskSupervisor},
        AgenticRealms.World.NPCChat.Registry,
        AgenticRealms.World.NPCChat.Supervisor,
        AgenticRealms.World.NPCChat.TaskSupervisor,
        AgenticRealms.World.Ticks.Subsystem
      ] ++
        commanded_children() ++
        [
          AgenticRealmsWeb.Endpoint
        ]

    opts = [strategy: :one_for_one, name: AgenticRealms.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp commanded_children do
    if Application.get_env(:agenticrealms, :start_commanded?, true) do
      [
        AgenticRealms.World.Application,
        AgenticRealms.World.Projections.WorldProjector,
        AgenticRealms.World.Projections.PlayerStateProjector,
        AgenticRealms.World.Projections.QuestProjector,
        AgenticRealms.World.Progression.XpAwarder,
        AgenticRealms.World.Projections.BlueprintProjector,
        AgenticRealms.World.Projections.EntityProjector,
        AgenticRealms.World.UIEventBroadcaster,
        AgenticRealms.World.Behaviors.Interpreter,
        AgenticRealms.NpcMinds.LifecycleManager,
        AgenticRealms.World.Transient.Registry,
        AgenticRealms.World.Transient.Supervisor,
        %{
          id: AgenticRealms.World.Transient.ManagerStarter,
          start:
            {Task, :start_link, [&AgenticRealms.World.Transient.Supervisor.ensure_manager/0]},
          restart: :transient
        },
        AgenticRealms.NpcMinds.Registry,
        AgenticRealms.NpcMinds.Supervisor,
        %{
          id: AgenticRealms.NpcMinds.ReconcilerStarter,
          start: {Task, :start_link, [&AgenticRealms.NpcMinds.Supervisor.ensure_reconciler/0]},
          restart: :transient
        }
      ]
    else
      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    AgenticRealmsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
