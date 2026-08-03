defmodule AgenticRealms.NpcMinds.Registry do
  @moduledoc """
  Cluster-wide unique registry for the singleton
  `NpcMinds.Reconciler` (same `Horde.Registry` pattern as `Ticks.Registry` /
  `NPCChat.Registry`). A single fixed key (`:reconciler`) maps to exactly one
  reconciler pid across the BEAM cluster, so the periodic sweep runs on one node
  only and is relocated by Horde when that node leaves.
  """

  @singleton_key :reconciler

  @doc false
  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {Horde.Registry, :start_link, [[name: __MODULE__, keys: :unique, members: :auto]]},
      type: :supervisor
    }
  end

  @doc "The `:via` tuple naming the singleton reconciler."
  @spec via_tuple() :: {:via, Horde.Registry, {module(), atom()}}
  def via_tuple, do: {:via, Horde.Registry, {__MODULE__, @singleton_key}}

  @doc "Look up the singleton reconciler pid. `{:ok, pid}` or `:error`."
  @spec lookup() :: {:ok, pid()} | :error
  def lookup do
    case Horde.Registry.lookup(__MODULE__, @singleton_key) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end
end
