defmodule AgenticRealms.World.Projections.PlayerStateProjector do
  @moduledoc """
  Projects player lifecycle events into the `player_state` read model.

  Event handler clauses added so far:
    * Phase 4 (US1): PlayerSpawned    → upsert player_state.current_room_id
    * Phase 5 (US2): PlayerMoved      → update player_state.current_room_id
                                        (with FR-022 nilify if target room gone)
    * Feature 020:   CharacterCreated → upsert the character columns

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

  alias AgenticRealms.World.Events.{
    CharacterCreated,
    PlayerSpawned,
    PlayerMoved,
    PlayerXpAwarded,
    PlayerLeveledUp
  }

  alias AgenticRealms.World.Schemas.{PlayerState, Room}

  # Feature 020 — the character columns. An upsert, like the PlayerSpawned
  # clause: `ensure_character/1` runs first at mount so this is normally the
  # insert that creates the row, but neither clause may assume the other has
  # run — a replay from position 0 can deliver them in either order.
  #
  # Every value is absolute and comes from the event, so re-handling is a no-op.
  # The `on_conflict` set names only the character columns, so a redelivered
  # CharacterCreated cannot reset current_room_id, xp, or level.
  def handle(%CharacterCreated{} = e, _meta) do
    now = utc_now()
    abilities = normalize_abilities(e.abilities)

    # What the event is authoritative about: who the character is. Set on
    # insert and on conflict alike, because the event is the record of them.
    identity = [
      # Feature 021 — the player's own choices. Set on insert and on conflict
      # alike, like every other identity column: the event is the record of who
      # the character is, so re-handling it can only write the same values.
      character_name: e.character_name,
      lineage_slug: e.lineage_slug,
      choices: e.choices || %{},
      species_slug: e.species_slug,
      class_slug: e.class_slug,
      background_slug: e.background_slug,
      size: e.size,
      str: abilities.str,
      dex: abilities.dex,
      con: abilities.con,
      int: abilities.int,
      wis: abilities.wis,
      cha: abilities.cha,
      max_hp: e.max_hp,
      skill_proficiencies: e.skill_proficiencies,
      save_proficiencies: e.save_proficiencies,
      feat_slugs: e.feat_slugs
    ]

    # What it only *seeds*: progression and current health. A redelivered or
    # replayed CharacterCreated must never knock a level 7 player back to 1, so
    # on conflict these are kept when already present and filled in only when
    # PlayerSpawned made the row and left them empty.
    seeded = [level: 1, xp: 0, hp: e.hp]

    Repo.insert!(
      struct!(
        PlayerState,
        [player_id: e.player_id, inserted_at: now, updated_at: now] ++ identity ++ seeded
      ),
      on_conflict:
        from(ps in PlayerState,
          update: [set: ^(identity ++ [updated_at: now])],
          update: [
            set: [
              level: fragment("COALESCE(?, 1)", ps.level),
              xp: fragment("COALESCE(?, 0)", ps.xp),
              hp: fragment("COALESCE(?, ?)", ps.hp, ^e.hp)
            ]
          ]
        ),
      conflict_target: :player_id
    )

    :ok
  end

  def handle(%PlayerSpawned{player_id: pid, room_id: room_id}, _meta) do
    now = utc_now()

    # `on_conflict` intentionally sets ONLY current_room_id so a
    # redelivered/replayed PlayerSpawned never resets a player's character or
    # earned xp/level — those are written by their own event clauses.
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

  # Abilities come back from the event store with string keys.
  defp normalize_abilities(abilities) do
    Map.new(~w(str dex con int wis cha)a, fn key ->
      {key, abilities[key] || Map.fetch!(abilities, Atom.to_string(key))}
    end)
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
