defmodule AgenticRealms.World.Transient.Registry do
  @moduledoc """
  Cluster-wide unique registry for the singleton `Transient.Manager`
  (same `Horde.Registry` pattern as `NpcMinds.Registry` /
  `Ticks.Registry`). A single fixed key (`:manager`) maps to exactly one
  manager pid across the BEAM cluster.

  The manager was previously registered under a bare local name, which meant
  one copy per node. Its reaper does not merely observe: it dispatches
  `DestroyRegion` and then **hard-deletes event-store streams**, and two nodes
  sweeping concurrently both pass the "does this region still exist?" check
  before either finishes. Making it a cluster singleton is what stops that,
  and it removes the duplicated sweep work as well.
  """

  @singleton_key :manager

  @doc false
  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {Horde.Registry, :start_link, [[name: __MODULE__, keys: :unique, members: :auto]]},
      type: :supervisor
    }
  end

  @doc "The `:via` tuple naming the singleton manager."
  @spec via_tuple() :: {:via, Horde.Registry, {module(), atom()}}
  def via_tuple, do: {:via, Horde.Registry, {__MODULE__, @singleton_key}}

  @doc "Look up the singleton manager pid. `{:ok, pid}` or `:error`."
  @spec lookup() :: {:ok, pid()} | :error
  def lookup do
    case Horde.Registry.lookup(__MODULE__, @singleton_key) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end
end
