defmodule AgenticRealms.World.Projections.PlayerStateProjector do
  @moduledoc """
  Projects player lifecycle events into the `player_state` read model.

  Event handler clauses added so far:
    * Phase 4 (US1): PlayerSpawned → upsert player_state.current_room_id
    * Phase 5 (US2): PlayerMoved   → update player_state.current_room_id
                                     (with FR-022 nilify if target room gone)

  All upserts use `on_conflict: :replace_all` so replays are safe.
  """

  # `:strong` so callers can dispatch SpawnPlayer (and MovePlayer)
  # with `consistency: :strong` and be guaranteed that the `player_state`
  # row is in place by the time the dispatch returns. Without this the
  # LiveView's mount races the projector and crashes for new players.
  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :strong

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Commands, as: WorldCommands
  alias AgenticRealms.World.Events.{PlayerSpawned, PlayerMoved, PlayerXpAwarded, PlayerLeveledUp}
  alias AgenticRealms.World.Schemas.{PlayerState, Room}

  def handle(%PlayerSpawned{player_id: pid, room_id: room_id}, _meta) do
    now = utc_now()

    # Feature 019 — Real Stats. Starting stats (abilities 12, level 1, xp 0,
    # hp/mana 10/10) are seeded on first insert via the `PlayerState` schema
    # field defaults. `on_conflict` intentionally sets ONLY current_room_id so
    # a redelivered/replayed PlayerSpawned never resets a player's earned
    # xp/level — those are updated by their own event clauses below.
    Repo.insert!(
      %PlayerState{
        player_id: pid,
        current_room_id: room_id,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: [set: [current_room_id: room_id, updated_at: now]],
      conflict_target: :player_id
    )

    # Feature 012 — Maps. Unconditionally dispatch RecordRoomDiscovery; the
    # World.Player aggregate's in-process MapSet decides whether to emit a
    # PlayerDiscoveredRoom event. The projector NEVER pre-checks the read
    # model — that would create a back door around event sourcing.
    :ok = WorldCommands.record_room_discovery(pid, room_id)

    :ok
  end

  def handle(%PlayerMoved{player_id: pid, to_room_id: to}, _meta) do
    # FR-022: if the destination room has been removed from the world
    # (e.g., the seed was reshaped), null out current_room_id so the
    # next Play visit triggers a fresh SpawnPlayer into the starter room.
    target =
      if room_exists?(to) do
        to
      else
        nil
      end

    now = utc_now()

    Repo.update_all(
      from(ps in PlayerState, where: ps.player_id == ^pid),
      set: [current_room_id: target, updated_at: now]
    )

    # Feature 012 — Maps. Dispatch discovery if the destination room is
    # real (preserves the existing FR-022 guard for purged-destination
    # safety). Aggregate handles idempotency for already-discovered rooms.
    if not is_nil(target) do
      :ok = WorldCommands.record_room_discovery(pid, target)
    end

    :ok
  end

  # Feature 019 — Real Stats. Progression updates. `new_total`/`to_level` are
  # absolute values from the event, so re-handling is idempotent.
  def handle(%PlayerXpAwarded{player_id: pid, new_total: new_total}, _meta) do
    Repo.update_all(
      from(ps in PlayerState, where: ps.player_id == ^pid),
      set: [xp: new_total, updated_at: utc_now()]
    )

    :ok
  end

  def handle(%PlayerLeveledUp{player_id: pid, to_level: to_level}, _meta) do
    Repo.update_all(
      from(ps in PlayerState, where: ps.player_id == ^pid),
      set: [level: to_level, updated_at: utc_now()]
    )

    :ok
  end

  defp room_exists?(room_id) do
    Repo.exists?(from(r in Room, where: r.id == ^room_id))
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
