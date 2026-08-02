defmodule AgenticRealms.World.Transient.Supervisor do
  @moduledoc """
  Cluster-wide dynamic supervisor for the singleton `Transient.Manager`
  (feature 017; same `Horde.DynamicSupervisor` pattern as `NpcMinds.Supervisor`
  / `Ticks.Supervisor`).

  Horde places the manager on one node and **redistributes it to a surviving
  node** if that node leaves, so the reaper keeps running after node loss
  without a `:global` single-point dependency (Constitution Principle I).
  """

  alias AgenticRealms.World.Transient.{Manager, Registry}

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
  Ensure the singleton manager is running somewhere in the cluster. Idempotent:
  every node may call this at boot; the first start wins and the rest resolve to
  the same pid (Horde dedupes by the registry via-name). Returns `{:ok, pid}`.
  """
  @spec ensure_manager() :: {:ok, pid()} | {:error, term()}
  def ensure_manager do
    case Registry.lookup() do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        spec = %{
          id: Manager,
          start: {Manager, :start_link, [[]]},
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
end
