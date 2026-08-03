defmodule AgenticRealms.World.Ticks.Supervisor do
  @moduledoc """
  Cluster-wide dynamic supervisor for per-room `Scheduler` processes.
  Wraps `Horde.DynamicSupervisor`. Same pattern as
  `NPCChat.Supervisor`.
  """

  alias AgenticRealms.World.Ticks.{Registry, Scheduler}

  @doc false
  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start:
        {Horde.DynamicSupervisor, :start_link,
         [
           [
             name: __MODULE__,
             strategy: :one_for_one,
             members: :auto,
             distribution_strategy: Horde.UniformDistribution
           ]
         ]},
      type: :supervisor
    }
  end

  @doc """
  Find an existing Scheduler pid for `room_id` or start one if none is
  registered. Returns `{:ok, pid}` either way.
  """
  @spec find_or_start(room_id :: String.t()) :: {:ok, pid()} | {:error, term()}
  def find_or_start(room_id) when is_binary(room_id) do
    case Registry.lookup(room_id) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        spec = %{
          id: Scheduler,
          start: {Scheduler, :start_link, [room_id]},
          restart: :transient,
          shutdown: 5_000
        }

        case Horde.DynamicSupervisor.start_child(__MODULE__, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end

  @doc """
  Terminate the Scheduler for `room_id`, if it is registered. Used by
  `Lifecycle` after the leave-grace expires with zero live occupants.
  """
  @spec terminate(room_id :: String.t()) :: :ok | {:error, :not_found}
  def terminate(room_id) when is_binary(room_id) do
    case Registry.lookup(room_id) do
      {:ok, pid} -> Horde.DynamicSupervisor.terminate_child(__MODULE__, pid)
      :error -> {:error, :not_found}
    end
  end
end
