defmodule AgenticRealms.World.NPCChat.Registry do
  @moduledoc """
  Cluster-wide unique registry for `NPCChat.Conversation` processes
  (feature 010).

  Wraps `Horde.Registry` so that a `(player_id, npc_clone_id)` pair maps
  to exactly one Conversation pid across the BEAM cluster. CRDT-backed,
  with automatic membership via `members: :auto` (rides on top of
  `:net_kernel`'s node monitoring, which DNSCluster already drives).

  Callers use `via_tuple/1` to register or look up by key.
  """

  @doc false
  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {Horde.Registry, :start_link, [[name: __MODULE__, keys: :unique, members: :auto]]},
      type: :supervisor
    }
  end

  @doc """
  Build the `:via` tuple for a Conversation keyed by `{player_id,
  npc_clone_id}`. Pass as the `name:` option to `GenServer.start_link/2`
  or to `GenServer.call/3`.
  """
  @spec via_tuple({integer(), String.t()}) :: {:via, Horde.Registry, {module(), term()}}
  def via_tuple({player_id, npc_clone_id} = key)
      when is_integer(player_id) and is_binary(npc_clone_id) do
    {:via, Horde.Registry, {__MODULE__, key}}
  end

  @doc """
  Look up the pid for a key. Returns `{:ok, pid}` if a Conversation is
  registered, `:error` otherwise.
  """
  @spec lookup({integer(), String.t()}) :: {:ok, pid()} | :error
  def lookup(key) do
    case Horde.Registry.lookup(__MODULE__, key) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end
end
