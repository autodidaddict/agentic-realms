defmodule AgenticRealms.NpcMinds.Supervisor do
  @moduledoc """
  Feature 018 — cluster-wide dynamic supervisor for the singleton
  `NpcMinds.Reconciler` (same `Horde.DynamicSupervisor` pattern as
  `Ticks.Supervisor` / `NPCChat.Supervisor`). Horde places the reconciler on one
  node and **redistributes it to a surviving node** if that node leaves, so the
  reconciliation backstop keeps running after node loss — with no `:global`
  single-point dependency (Constitution Principle I).
  """

  alias AgenticRealms.NpcMinds.{Registry, Reconciler}

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
  Ensure the singleton reconciler is running somewhere in the cluster. Idempotent:
  every node may call this at boot; the first start wins and the rest resolve to
  the same pid (Horde dedupes by the registry via-name). Returns `{:ok, pid}`.
  """
  @spec ensure_reconciler() :: {:ok, pid()} | {:error, term()}
  def ensure_reconciler do
    case Registry.lookup() do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        spec = %{
          id: Reconciler,
          start: {Reconciler, :start_link, [[]]},
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
