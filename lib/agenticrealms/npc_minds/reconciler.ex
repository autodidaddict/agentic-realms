defmodule AgenticRealms.NpcMinds.Reconciler do
  @moduledoc """
  Feature 018 — cluster-singleton reconciliation sweep. The event-driven lifecycle
  handoff (`LifecycleManager`) is best-effort, so a start/terminate issued while
  Temporal is unreachable is lost. This periodic sweep converges the set of
  running minds to the set of live NPCs: it starts a mind for any live NPC that
  has none and terminates any running mind whose NPC no longer exists (FR-029a,
  SC-013). Every operation is idempotent (Temporal `USE_EXISTING` start /
  tolerant terminate), so the sweep is safe to repeat.

  **Cluster semantics (Principle I).** Runs as a Horde cluster singleton: started
  under `NpcMinds.Supervisor` (a `Horde.DynamicSupervisor`) and named via
  `NpcMinds.Registry` (a `Horde.Registry`), so exactly one instance runs
  cluster-wide and Horde **relocates it to a surviving node** if the owning node
  leaves. Same mechanism the project uses for tick schedulers and NPC chats.
  """

  use GenServer

  require Logger
  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Schemas.NPCClone
  alias AgenticRealms.NpcMinds.{Config, Registry, TemporalClient}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Registry.via_tuple())
  end

  @doc "Run one reconciliation sweep synchronously. Test/ops helper."
  @spec sweep_now() :: {:ok, map()} | {:error, term()}
  def sweep_now, do: GenServer.call(Registry.via_tuple(), :sweep, 30_000)

  @doc """
  Pure diff of the two id sets: which NPC ids need a mind started (live but not
  running) and which running minds need terminating (running but not live).
  """
  @spec diff(Enumerable.t(), Enumerable.t()) :: %{
          to_start: [String.t()],
          to_terminate: [String.t()]
        }
  def diff(live, running) do
    live_set = MapSet.new(live)
    running_set = MapSet.new(running)

    %{
      to_start: live_set |> MapSet.difference(running_set) |> MapSet.to_list(),
      to_terminate: running_set |> MapSet.difference(live_set) |> MapSet.to_list()
    }
  end

  @impl true
  def init(_opts) do
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    _ = do_sweep()
    schedule_sweep()
    {:noreply, state}
  end

  @impl true
  def handle_call(:sweep, _from, state), do: {:reply, do_sweep(), state}

  defp do_sweep do
    case TemporalClient.list_running_npc_ids() do
      {:ok, running} ->
        %{to_start: to_start, to_terminate: to_terminate} = diff(live_npc_ids(), running)
        Enum.each(to_start, &TemporalClient.start_workflow/1)
        Enum.each(to_terminate, &TemporalClient.terminate_workflow/1)
        {:ok, %{started: length(to_start), terminated: length(to_terminate)}}

      {:error, reason} ->
        Logger.warning("NPC mind reconcile skipped (Temporal unavailable): #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp live_npc_ids, do: Repo.all(from(c in NPCClone, select: c.id))

  defp schedule_sweep, do: Process.send_after(self(), :sweep, Config.reconcile_interval_ms())
end
