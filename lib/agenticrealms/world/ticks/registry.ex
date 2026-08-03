defmodule AgenticRealms.World.Ticks.Registry do
  @moduledoc """
  Cluster-wide unique registry for `RoomTicks.Scheduler` processes
  (feature 011).

  Wraps `Horde.Registry` so a `room_id` maps to exactly one Scheduler
  pid across the BEAM cluster. Same pattern as `NPCChat.Registry`
  from feature 010.
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
  Build the `:via` tuple for a Scheduler keyed by `room_id`.
  """
  @spec via_tuple(room_id :: String.t()) :: {:via, Horde.Registry, {module(), String.t()}}
  def via_tuple(room_id) when is_binary(room_id) do
    {:via, Horde.Registry, {__MODULE__, room_id}}
  end

  @doc """
  Look up the pid for a room_id. Returns `{:ok, pid}` if a Scheduler is
  registered, `:error` otherwise.
  """
  @spec lookup(room_id :: String.t()) :: {:ok, pid()} | :error
  def lookup(room_id) when is_binary(room_id) do
    case Horde.Registry.lookup(__MODULE__, room_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end
end
