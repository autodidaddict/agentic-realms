defmodule AgenticRealms.World.Projections.PlayerStateProjector do
  @moduledoc """
  Projects player lifecycle events into the `player_state` read model.

  Event handler clauses added so far:
    * Phase 4: PlayerSpawned    → upsert player_state.current_room_id
    * Phase 5: PlayerMoved      → update player_state.current_room_id
                                        (nilified if the target room is gone)
    * CharacterCreated          → upsert the character columns

  All upserts use `on_conflict: :replace_all` so replays are safe.
  """

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

  def handle(%CharacterCreated{} = e, _meta) do
    now = utc_now()
    abilities = normalize_abilities(e.abilities)

    identity = [
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

    :ok = WorldCommands.record_room_discovery(pid, room_id)

    :ok
  end

  def handle(%PlayerMoved{player_id: pid, to_room_id: to}, _meta) do
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

    if not is_nil(target) do
      :ok = WorldCommands.record_room_discovery(pid, target)
    end

    :ok
  end

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

  defp normalize_abilities(abilities) do
    Map.new(~w(str dex con int wis cha)a, fn key ->
      {key, abilities[key] || Map.fetch!(abilities, Atom.to_string(key))}
    end)
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
