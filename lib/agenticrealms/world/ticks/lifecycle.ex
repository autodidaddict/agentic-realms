defmodule AgenticRealms.World.Ticks.Lifecycle do
  @moduledoc """
  Singleton GenServer that detects 0↔1 live-occupancy transitions per
  room and starts/stops `RoomTicks.Scheduler` processes accordingly,
  with join/leave grace periods to absorb reconnect bursts.

  Lives under the application supervisor with a fixed registered name.
  NOT under Horde — in multi-node deployments, each node observes
  Presence independently and `find_or_start/1` is idempotent across
  registry calls (Horde.Registry enforces uniqueness).

  See `specs/011-room-tick-timers/contracts/lifecycle.md`.
  """

  use GenServer

  require Logger

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.Room
  alias AgenticRealms.World.Ticks.Supervisor, as: TicksSupervisor

  alias AgenticRealms.World.UIEvents.{
    PlayerCurrentRoomChanged,
    RoomPlayerArrived,
    RoomPlayerLeft
  }

  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub

  defstruct live_per_room: %{},
            pending_join: %{},
            pending_leave: %{},
            started_schedulers: MapSet.new(),
            subscribed_rooms: MapSet.new()

  # --- Client -------------------------------------------------------------

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Test/debug-only state inspection."
  @spec get_state() :: %__MODULE__{}
  def get_state, do: GenServer.call(__MODULE__, :get_state)

  @doc """
  Test helper: inject a room event as if it had been received via PubSub.
  Routes through the same handle_info clauses production traffic uses.
  """
  @spec notify(term()) :: term()
  def notify(event), do: send(__MODULE__, event)

  # --- Server -------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Subscribe to the global "connected_players" Presence topic so we
    # learn about online/offline transitions.
    Phoenix.PubSub.subscribe(@pubsub, AgenticRealmsWeb.Presence.topic())

    # Eagerly subscribe to every existing room's topic. We need this so
    # cross-room MOVES (which emit RoomPlayerArrived on the destination
    # room_topic without firing a Presence diff) reach the Lifecycle.
    # Lazy subscription on first-arrival doesn't work for moves: the
    # first arrival event IS the signal that's broadcast on a topic we
    # haven't subscribed to yet.
    state =
      Repo.all(Room)
      |> Enum.reduce(%__MODULE__{}, fn %Room{id: room_id}, st ->
        ensure_room_subscription(st, room_id)
      end)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  # --- 0 → ≥1 path (T031, US1) -------------------------------------------

  @impl true
  def handle_info(%RoomPlayerArrived{room_id: room_id, actor_id: player_id}, state) do
    state =
      state
      |> ensure_room_subscription(room_id)
      |> add_to_room(room_id, player_id)
      |> occupancy_changed(room_id)

    {:noreply, state}
  end

  # --- ≥1 → 0 path (T037, US2) -------------------------------------------

  def handle_info(%RoomPlayerLeft{room_id: room_id, actor_id: player_id}, state) do
    state =
      state
      |> remove_from_room(room_id, player_id)
      |> occupancy_changed(room_id)

    {:noreply, state}
  end

  # Cross-room move — handled the same way as a paired Left/Arrived; the
  # broadcaster already emits those, but PlayerCurrentRoomChanged is also
  # broadcast to the player's player_topic. We do NOT subscribe to that
  # topic (not our concern), but if the message ever arrives here we
  # tolerate it gracefully.
  def handle_info(%PlayerCurrentRoomChanged{}, state), do: {:noreply, state}

  # Phoenix.Presence diff for the global "connected_players" topic.
  # Online → add player_id to their `current_room_id` set if known.
  # Offline → remove player_id from any room set they're in.
  def handle_info(%{event: "presence_diff", payload: %{joins: joins, leaves: leaves}}, state) do
    state =
      state
      |> apply_presence_joins(joins)
      |> apply_presence_leaves(leaves)

    {:noreply, state}
  end

  # Self-message: join grace expired — start the scheduler if still
  # occupied.
  def handle_info({:start_scheduler, room_id}, state) do
    state = clear_pending_join(state, room_id)

    if room_live_count(state, room_id) > 0 do
      case TicksSupervisor.find_or_start(room_id) do
        {:ok, _pid} ->
          Logger.debug("RoomTicks.Lifecycle: started scheduler for room #{room_id}")
          {:noreply, %{state | started_schedulers: MapSet.put(state.started_schedulers, room_id)}}

        {:error, reason} ->
          Logger.warning(
            "RoomTicks.Lifecycle: failed to start scheduler for room #{room_id}: #{inspect(reason)}"
          )

          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Self-message: leave grace expired — stop the scheduler if still
  # empty.
  def handle_info({:stop_scheduler, room_id}, state) do
    state = clear_pending_leave(state, room_id)

    if room_live_count(state, room_id) == 0 and MapSet.member?(state.started_schedulers, room_id) do
      _ = TicksSupervisor.terminate(room_id)
      Logger.debug("RoomTicks.Lifecycle: stopped scheduler for room #{room_id}")
      {:noreply, %{state | started_schedulers: MapSet.delete(state.started_schedulers, room_id)}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  # --- Internal helpers ---------------------------------------------------

  defp ensure_room_subscription(state, room_id) do
    if MapSet.member?(state.subscribed_rooms, room_id) do
      state
    else
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(room_id))
      %{state | subscribed_rooms: MapSet.put(state.subscribed_rooms, room_id)}
    end
  end

  defp add_to_room(state, room_id, player_id) do
    set = state.live_per_room |> Map.get(room_id, MapSet.new()) |> MapSet.put(player_id)
    %{state | live_per_room: Map.put(state.live_per_room, room_id, set)}
  end

  defp remove_from_room(state, room_id, player_id) do
    set = state.live_per_room |> Map.get(room_id, MapSet.new()) |> MapSet.delete(player_id)
    %{state | live_per_room: Map.put(state.live_per_room, room_id, set)}
  end

  defp room_live_count(state, room_id) do
    state.live_per_room |> Map.get(room_id, MapSet.new()) |> MapSet.size()
  end

  defp occupancy_changed(state, room_id) do
    count = room_live_count(state, room_id)
    started? = MapSet.member?(state.started_schedulers, room_id)

    cond do
      count > 0 and not started? -> schedule_start(state, room_id)
      count == 0 and started? -> schedule_stop(state, room_id)
      count > 0 and started? -> clear_pending_leave(state, room_id)
      count == 0 and not started? -> state
    end
  end

  defp schedule_start(state, room_id) do
    state = clear_pending_leave(state, room_id)

    # If a join is already pending, leave it in place — it'll fire when
    # the timer expires.
    if Map.has_key?(state.pending_join, room_id) do
      state
    else
      ref = Process.send_after(self(), {:start_scheduler, room_id}, join_grace_ms())
      %{state | pending_join: Map.put(state.pending_join, room_id, ref)}
    end
  end

  defp schedule_stop(state, room_id) do
    state = clear_pending_join(state, room_id)

    if Map.has_key?(state.pending_leave, room_id) do
      state
    else
      ref = Process.send_after(self(), {:stop_scheduler, room_id}, leave_grace_ms())
      %{state | pending_leave: Map.put(state.pending_leave, room_id, ref)}
    end
  end

  defp clear_pending_join(state, room_id) do
    case Map.pop(state.pending_join, room_id) do
      {nil, _} ->
        state

      {ref, rest} ->
        _ = Process.cancel_timer(ref)
        %{state | pending_join: rest}
    end
  end

  defp clear_pending_leave(state, room_id) do
    case Map.pop(state.pending_leave, room_id) do
      {nil, _} ->
        state

      {ref, rest} ->
        _ = Process.cancel_timer(ref)
        %{state | pending_leave: rest}
    end
  end

  defp apply_presence_joins(state, joins) do
    Enum.reduce(joins, state, fn {pid_str, _meta}, st ->
      with {player_id, ""} <- Integer.parse(to_string(pid_str)),
           {:ok, room_id} <- Queries.current_room_of(player_id) do
        st
        |> ensure_room_subscription(room_id)
        |> add_to_room(room_id, player_id)
        |> occupancy_changed(room_id)
      else
        _ -> st
      end
    end)
  end

  defp apply_presence_leaves(state, leaves) do
    Enum.reduce(leaves, state, fn {pid_str, _meta}, st ->
      with {player_id, ""} <- Integer.parse(to_string(pid_str)) do
        # Walk every room set and remove the player; trigger occupancy
        # checks for each room they were in.
        rooms_with_player =
          Enum.filter(st.live_per_room, fn {_room_id, set} -> MapSet.member?(set, player_id) end)

        Enum.reduce(rooms_with_player, st, fn {room_id, _set}, acc ->
          acc
          |> remove_from_room(room_id, player_id)
          |> occupancy_changed(room_id)
        end)
      else
        _ -> st
      end
    end)
  end

  defp join_grace_ms do
    Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])
    |> Keyword.get(:join_grace_ms, 250)
  end

  defp leave_grace_ms do
    Application.get_env(:agenticrealms, AgenticRealms.World.Ticks, [])
    |> Keyword.get(:leave_grace_ms, 5_000)
  end
end
