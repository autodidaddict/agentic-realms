defmodule AgenticRealms.World.Transient.Manager do
  @moduledoc """
  Singleton lifecycle manager for transient regions. Two duties,
  both driven off durable `regions` columns so there is nothing to rehydrate
  after a crash:

    * **Presence stamping**: subscribes to the `"connected_players"` topic and
      keeps `owner_offline_since` in sync — cleared while the owner is online,
      stamped when they first go offline (the `leaves` for a player's last
      session). A reconnect clears the stamp, which is the implicit grace.
    * **Timed reaper**: every `reap_interval_ms` it sweeps transient regions and
      destroys + purges any that are due — owner logged off past the grace, the
      60-minute cap elapsed, or already tombstoned (crash-recovery retry).

  **Exactly one runs cluster-wide**, placed by `Transient.Supervisor` (a
  `Horde.DynamicSupervisor`) and named through `Transient.Registry`, which
  relocates it to a surviving node if its own node leaves.

  That is not decoration. The reaper does not merely observe: it dispatches
  `DestroyRegion` and then hard-deletes event-store streams via `Purge.run/1`.
  `Transient.destroy/1` is idempotent across *sequential* calls — a missing
  region returns `:ok` — but two nodes sweeping at once both pass that check
  before either reaches the purge. One manager, one sweep.

  After a restart the next sweep re-derives "due" from durable state, so
  regions that became abandoned during downtime are reaped, and a
  crash midway through a purge is retried by the tombstone clause in `due?/2`.
  """

  use GenServer

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Schemas.Region
  alias AgenticRealms.World.Transient
  alias AgenticRealms.World.Transient.Registry
  alias AgenticRealmsWeb.Presence

  @pubsub AgenticRealms.PubSub

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Registry.via_tuple())

  @doc """
  Synchronously run a reap sweep and return the list of reaped region ids.
  Used by tests/ops to drive the reaper deterministically instead of waiting
  for the periodic timer.
  """
  @spec sweep_now() :: [String.t()]
  def sweep_now, do: GenServer.call(Registry.via_tuple(), :sweep_now, 30_000)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(@pubsub, Presence.topic())
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:sweep_now, _from, state), do: {:reply, do_sweep(), state}

  @impl true
  def handle_info(:sweep, state) do
    _ = do_sweep()
    schedule_sweep()
    {:noreply, state}
  end

  def handle_info(%{event: "presence_diff"}, state) do
    _ = do_reconcile()
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp do_sweep do
    now = DateTime.utc_now()
    online = online_ids()

    transient_regions()
    |> Enum.map(&reconcile_offline(&1, online, now))
    |> Enum.filter(&due?(&1, now))
    |> Enum.map(fn region ->
      Transient.destroy(region.id)
      region.id
    end)
  end

  defp do_reconcile do
    now = DateTime.utc_now()
    online = online_ids()
    transient_regions() |> Enum.each(&reconcile_offline(&1, online, now))
    :ok
  end

  defp transient_regions, do: Repo.all(from(r in Region, where: r.kind == "transient"))

  defp reconcile_offline(%Region{} = region, online, now) do
    online? = MapSet.member?(online, region.provision_owner_id)

    cond do
      online? and not is_nil(region.owner_offline_since) ->
        set_offline_since(region.id, nil)
        %{region | owner_offline_since: nil}

      not online? and is_nil(region.owner_offline_since) ->
        set_offline_since(region.id, now)
        %{region | owner_offline_since: now}

      true ->
        region
    end
  end

  defp due?(%Region{destroyed_at: destroyed_at}, _now) when not is_nil(destroyed_at), do: true
  defp due?(%Region{} = region, now), do: logoff_due?(region, now) or cap_due?(region, now)

  defp logoff_due?(%Region{owner_offline_since: nil}, _now), do: false

  defp logoff_due?(%Region{owner_offline_since: since}, now),
    do: DateTime.diff(now, since, :millisecond) >= grace_ms()

  defp cap_due?(%Region{provisioned_at: nil}, _now), do: false

  defp cap_due?(%Region{provisioned_at: at}, now),
    do: DateTime.diff(now, at, :millisecond) >= lifetime_ms()

  defp set_offline_since(region_id, value) do
    from(r in Region, where: r.id == ^region_id)
    |> Repo.update_all(set: [owner_offline_since: value])
  end

  defp online_ids do
    Presence.list(Presence.topic())
    |> Map.keys()
    |> Enum.map(&String.to_integer/1)
    |> MapSet.new()
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, reap_interval_ms())

  defp config, do: Application.get_env(:agenticrealms, AgenticRealms.World.Transient, [])
  defp grace_ms, do: Keyword.get(config(), :logoff_grace_ms, 120_000)
  defp lifetime_ms, do: Keyword.get(config(), :region_lifetime_ms, 3_600_000)
  defp reap_interval_ms, do: Keyword.get(config(), :reap_interval_ms, 30_000)
end
