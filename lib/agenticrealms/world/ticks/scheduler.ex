defmodule AgenticRealms.World.Ticks.Scheduler do
  @moduledoc """
  Per-room tick Scheduler GenServer (feature 011).

  One Scheduler per active room, registered cluster-wide in
  `RoomTicks.Registry` under key `room_id`. Owns the beat timer, the
  in-scope tick-behavior set, the per-behavior `last_fire` map, and the
  dispatch loop.

  Cadence is drift-free: `next_fire = last_fire + interval_ms`. Long
  actions don't pile up — a behavior whose previous tick is still
  dispatching is skipped on the current beat (FR-010, future-proofing).

  See `specs/011-room-tick-timers/contracts/scheduler.md`.
  """

  use GenServer

  require Logger

  alias AgenticRealms.World.Behaviors.ActionExecutor
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Ticks.{Registry, Scope}

  alias AgenticRealms.World.UIEvents.{
    RoomNPCArrived,
    RoomNPCLeft,
    RoomObjectDropped,
    RoomObjectTaken,
    RoomPlayerArrived,
    RoomPlayerLeft
  }

  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub

  defstruct [
    :room_id,
    :base_tick_rate_ms,
    :scheduler_start_time,
    in_scope: [],
    last_fire: %{},
    inflight: MapSet.new(),
    live_occupants: MapSet.new()
  ]

  # --- Client -------------------------------------------------------------

  @doc "Start a Scheduler registered for `room_id`."
  @spec start_link(room_id :: String.t()) :: GenServer.on_start()
  def start_link(room_id) when is_binary(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: Registry.via_tuple(room_id))
  end

  # --- Server -------------------------------------------------------------

  @impl true
  def init(room_id) do
    base = base_tick_rate_ms()

    Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(room_id))

    state = %__MODULE__{
      room_id: room_id,
      base_tick_rate_ms: base,
      scheduler_start_time: System.monotonic_time(:millisecond)
    }

    schedule_next_beat(base)

    # Scope and occupants are read from the database, which happens in
    # `handle_continue/2` rather than here for the same reason as
    # `Ticks.Lifecycle`: a process that cannot start on an unavailable database
    # restarts straight back into the query that stopped it. `handle_continue`
    # runs before any other message, so the scope is loaded before the first
    # beat is handled.
    {:ok, state, {:continue, :load_scope}}
  end

  @impl true
  def handle_continue(:load_scope, %__MODULE__{} = state) do
    state = %{
      state
      | in_scope: safe_db(fn -> Scope.compute(state.room_id) end, state.in_scope),
        live_occupants:
          safe_db(
            fn -> MapSet.new(Queries.live_occupants_of(state.room_id)) end,
            state.live_occupants
          )
    }

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call(:refresh, _from, state) do
    scope = safe_db(fn -> Scope.compute(state.room_id) end, state.in_scope)
    {:reply, :ok, %{state | in_scope: scope}}
  end

  @impl true
  def handle_info(:beat, %__MODULE__{} = state) do
    now = System.monotonic_time(:millisecond)
    due = filter_due(state, now)
    sorted = due

    state =
      Enum.reduce(sorted, state, fn entry, st ->
        Enum.each(entry.actions, fn action ->
          ActionExecutor.execute(entry.speaker_ctx, action, st.room_id, nil)
        end)

        %{st | last_fire: Map.put(st.last_fire, entry.key, now)}
      end)

    if sorted != [] do
      Logger.debug("RoomTicks.Scheduler[#{state.room_id}]: fired #{length(sorted)} behaviors")
    end

    schedule_next_beat(state.base_tick_rate_ms)
    {:noreply, state}
  end

  # --- Scope-change events ----------------------------------------------

  def handle_info(%RoomPlayerArrived{actor_id: pid, carried_object_ids: ids}, state) do
    state = %{state | live_occupants: MapSet.put(state.live_occupants, pid)}
    state = Enum.reduce(ids || [], state, &add_carried_object_state(&2, pid, &1))
    {:noreply, state}
  end

  def handle_info(%RoomPlayerLeft{actor_id: pid, carried_object_ids: ids}, state) do
    state = %{state | live_occupants: MapSet.delete(state.live_occupants, pid)}
    state = Enum.reduce(ids || [], state, &remove_carried_object_state(&2, pid, &1))
    {:noreply, state}
  end

  def handle_info(%RoomNPCArrived{npc_id: npc_id}, state) do
    # Reads the clone's behaviors, so it can fail like any other query.
    scope = safe_db(fn -> Scope.add_npc(state.in_scope, npc_id) end, state.in_scope)
    {:noreply, %{state | in_scope: scope}}
  end

  def handle_info(%RoomNPCLeft{npc_id: npc_id}, state) do
    new_scope = Scope.remove_npc(state.in_scope, npc_id)

    new_last_fire =
      Map.reject(state.last_fire, fn {{kind, id, _idx}, _} -> kind == :npc and id == npc_id end)

    {:noreply, %{state | in_scope: new_scope, last_fire: new_last_fire}}
  end

  # Object take/drop within the same room don't change scope — the
  # object is still in this room either way (just changes carrier
  # annotation, which we don't track in the scope set).
  def handle_info(%RoomObjectTaken{}, state), do: {:noreply, state}
  def handle_info(%RoomObjectDropped{}, state), do: {:noreply, state}

  def handle_info(_other, state), do: {:noreply, state}

  # --- Internal helpers --------------------------------------------------

  defp filter_due(%__MODULE__{} = state, now) do
    Enum.filter(state.in_scope, fn entry ->
      last = Map.get(state.last_fire, entry.key, state.scheduler_start_time)
      now - last >= entry.interval_ms and not MapSet.member?(state.inflight, entry.key)
    end)
  end

  defp schedule_next_beat(base_rate_ms) do
    Process.send_after(self(), :beat, base_rate_ms)
  end

  # Run a query, and survive the database not being there. Same reasoning as
  # `Ticks.Lifecycle.safe_db/2`: this process is long-lived and supervised, and
  # an exit here costs a restart into the same query rather than one stale
  # scope entry. Scope is recomputed on the next `:refresh` or scope event.
  defp safe_db(fun, fallback) do
    fun.()
  rescue
    error ->
      Logger.warning("Ticks.Scheduler: query failed (#{Exception.message(error)}); degrading")
      fallback
  catch
    :exit, reason ->
      Logger.warning("Ticks.Scheduler: query exited (#{inspect(reason)}); degrading")
      fallback
  end

  defp add_carried_object_state(%__MODULE__{} = state, player_id, object_id) do
    scope =
      safe_db(
        fn -> Scope.add_carried_object(state.in_scope, player_id, object_id) end,
        state.in_scope
      )

    %{state | in_scope: scope}
  end

  defp remove_carried_object_state(%__MODULE__{} = state, player_id, object_id) do
    new_scope = Scope.remove_carried_object(state.in_scope, player_id, object_id)

    new_last_fire =
      Map.reject(state.last_fire, fn {{kind, id, _idx}, _} ->
        kind == :object and id == object_id
      end)

    %{state | in_scope: new_scope, last_fire: new_last_fire}
  end

  defp base_tick_rate_ms do
    Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])
    |> Keyword.get(:base_tick_rate_ms, 1_000)
  end
end
