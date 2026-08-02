defmodule AgenticRealms.World.Player do
  @moduledoc """
  Player aggregate. Owns the player's current room only — inventory state
  lives in the `world_objects.player_id` read model, not on this aggregate
  (per data-model §1.2 final decision).

  Coexists with `AgenticRealms.Accounts.Player` (the account record); the
  two represent different things and modules consuming both should alias
  one of them to avoid ambiguity.

  See `specs/003-persisted-world/data-model.md` §1.2.
  """

  defstruct id: nil,
            current_room_id: nil,
            # Feature 012 — Maps. In-aggregate set of rooms this player has
            # personally entered. Authoritative idempotency check for
            # RecordRoomDiscovery — the projector NEVER pre-checks; it
            # unconditionally dispatches and relies on this MapSet to decide
            # whether to emit a PlayerDiscoveredRoom event. See
            # `specs/012-maps/contracts/discovery.md`.
            discovered_room_ids: MapSet.new(),
            # Feature 020 — SRD 5e Character Stats. Who the character is, set
            # once by CharacterCreated and nil until then. `species_slug` is the
            # aggregate's "does a character exist yet" guard.
            species_slug: nil,
            class_slug: nil,
            background_slug: nil,
            size: nil,
            # Feature 021 — what the player chose to be called, and their
            # lineage where their species offers one.
            character_name: nil,
            lineage_slug: nil,
            skill_proficiencies: [],
            save_proficiencies: [],
            feat_slugs: [],
            # Ability scores, progression and vitals. Aggregate-owned; nil until
            # CharacterCreated. Plain integers — no snapshot-serialization
            # treatment needed. Mana is gone: the SRD has no such resource.
            str: nil,
            dex: nil,
            con: nil,
            int: nil,
            wis: nil,
            cha: nil,
            level: nil,
            xp: nil,
            hp: nil,
            max_hp: nil,
            # Feature 019 — idempotency guard. award_ids already applied, so a
            # redelivered/replayed AwardXp is a no-op. Serialized like
            # discovered_room_ids (list on the wire, MapSet in memory).
            applied_award_ids: MapSet.new()

  alias AgenticRealms.World.Commands.{
    SpawnPlayer,
    MovePlayer,
    RecordRoomDiscovery,
    AwardXp,
    CreateCharacter
  }

  alias AgenticRealms.World.Events.{
    PlayerSpawned,
    PlayerMoved,
    PlayerDiscoveredRoom,
    PlayerXpAwarded,
    PlayerLeveledUp,
    CharacterCreated
  }

  alias Srd.Rules.Experience

  # --- SpawnPlayer --------------------------------------------------------

  @spec execute(
          %__MODULE__{},
          %SpawnPlayer{}
          | %MovePlayer{}
          | %RecordRoomDiscovery{}
          | %AwardXp{}
          | %CreateCharacter{}
        ) ::
          %PlayerSpawned{}
          | %PlayerMoved{}
          | %PlayerDiscoveredRoom{}
          | %PlayerXpAwarded{}
          | %CharacterCreated{}
          | [%PlayerXpAwarded{} | %PlayerLeveledUp{}]
          | :ok
          | {:error, atom()}
  def execute(%__MODULE__{current_room_id: nil}, %SpawnPlayer{
        player_id: pid,
        starting_room_id: room_id
      }) do
    %PlayerSpawned{player_id: pid, room_id: room_id}
  end

  def execute(%__MODULE__{}, %SpawnPlayer{}), do: {:error, :already_spawned}

  # --- MovePlayer ---------------------------------------------------------

  def execute(%__MODULE__{current_room_id: nil}, %MovePlayer{}),
    do: {:error, :not_spawned}

  def execute(%__MODULE__{current_room_id: current}, %MovePlayer{from_room_id: from})
      when current != from do
    {:error, :stale_from_room}
  end

  def execute(%__MODULE__{}, %MovePlayer{to_room_id: nil}),
    do: {:error, :no_target_room}

  def execute(%__MODULE__{}, %MovePlayer{
        player_id: pid,
        from_room_id: from,
        to_room_id: to,
        direction: direction
      }) do
    %PlayerMoved{
      player_id: pid,
      from_room_id: from,
      to_room_id: to,
      direction: direction
    }
  end

  # --- RecordRoomDiscovery (feature 012) ----------------------------------
  #
  # The aggregate's in-process MapSet is the authority for first-discovery.
  # The PlayerStateProjector dispatches RecordRoomDiscovery unconditionally
  # on every spawn / move; this clause short-circuits with :ok (no event)
  # when the room is already known, and emits exactly one
  # PlayerDiscoveredRoom event the first time.

  def execute(%__MODULE__{discovered_room_ids: discovered}, %RecordRoomDiscovery{
        player_id: pid,
        room_id: rid
      }) do
    if MapSet.member?(discovered, rid) do
      :ok
    else
      %PlayerDiscoveredRoom{
        player_id: pid,
        room_id: rid,
        discovered_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    end
  end

  # --- CreateCharacter (feature 020) --------------------------------------
  #
  # Guarded on `species_slug`: a character is made once. GameLive dispatches
  # this on every mount, so all but the first are no-ops — the same shape as
  # RecordRoomDiscovery, where the aggregate is the authority on whether the
  # thing has already happened.
  #
  # The command carries a fully-generated character. Nothing is looked up or
  # defaulted here, so replaying this stream reproduces exactly the character
  # that was created, no matter what the configured defaults have become since.

  def execute(%__MODULE__{species_slug: nil}, %CreateCharacter{} = cmd) do
    %CharacterCreated{
      player_id: cmd.player_id,
      character_name: cmd.character_name,
      species_slug: cmd.species_slug,
      class_slug: cmd.class_slug,
      background_slug: cmd.background_slug,
      size: cmd.size,
      lineage_slug: cmd.lineage_slug,
      abilities: cmd.abilities,
      skill_proficiencies: cmd.skill_proficiencies,
      save_proficiencies: cmd.save_proficiencies,
      feat_slugs: cmd.feat_slugs,
      choices: cmd.choices,
      hp: cmd.max_hp,
      max_hp: cmd.max_hp
    }
  end

  def execute(%__MODULE__{}, %CreateCharacter{}), do: :ok

  # --- AwardXp (feature 019) ----------------------------------------------
  #
  # Players only. Idempotent per `award_id` (a redelivered/replayed source
  # event is a no-op) and a no-op for non-positive amounts. Re-evaluates the
  # level against the curve and emits PlayerLeveledUp only when the level rises
  # (possibly by more than one level at once).

  def execute(%__MODULE__{} = state, %AwardXp{
        player_id: pid,
        amount: amount,
        award_id: award_id
      }) do
    cond do
      not is_integer(amount) or amount <= 0 ->
        :ok

      MapSet.member?(state.applied_award_ids, award_id) ->
        :ok

      true ->
        new_total = (state.xp || 0) + amount
        current_level = state.level || 1
        new_level = Experience.level_for_xp(new_total)

        awarded = %PlayerXpAwarded{
          player_id: pid,
          amount: amount,
          new_total: new_total,
          award_id: award_id
        }

        if new_level > current_level do
          [
            awarded,
            %PlayerLeveledUp{player_id: pid, from_level: current_level, to_level: new_level}
          ]
        else
          awarded
        end
    end
  end

  # --- apply/2 ------------------------------------------------------------

  @spec apply(
          %__MODULE__{},
          %PlayerSpawned{}
          | %PlayerMoved{}
          | %PlayerDiscoveredRoom{}
          | %PlayerXpAwarded{}
          | %PlayerLeveledUp{}
          | %CharacterCreated{}
        ) :: %__MODULE__{}
  def apply(%__MODULE__{} = state, %PlayerSpawned{player_id: pid, room_id: room_id}) do
    # Feature 020 — spawning means "entered the world", nothing more. Stats
    # arrive with CharacterCreated, which is the event that means a character
    # exists. Seeding placeholders here would let a spawned-but-uncreated player
    # look like a real character.
    %__MODULE__{state | id: pid, current_room_id: room_id}
  end

  def apply(%__MODULE__{} = state, %CharacterCreated{} = e) do
    abilities = normalize_abilities(e.abilities)

    %__MODULE__{
      state
      | id: e.player_id,
        character_name: e.character_name,
        species_slug: e.species_slug,
        class_slug: e.class_slug,
        background_slug: e.background_slug,
        size: e.size,
        lineage_slug: e.lineage_slug,
        skill_proficiencies: e.skill_proficiencies,
        save_proficiencies: e.save_proficiencies,
        feat_slugs: e.feat_slugs,
        str: abilities.str,
        dex: abilities.dex,
        con: abilities.con,
        int: abilities.int,
        wis: abilities.wis,
        cha: abilities.cha,
        level: 1,
        xp: 0,
        hp: e.hp,
        max_hp: e.max_hp
    }
  end

  def apply(%__MODULE__{} = state, %PlayerMoved{to_room_id: to}) do
    %__MODULE__{state | current_room_id: to}
  end

  def apply(%__MODULE__{discovered_room_ids: discovered} = state, %PlayerDiscoveredRoom{
        room_id: rid
      }) do
    %__MODULE__{state | discovered_room_ids: MapSet.put(discovered, rid)}
  end

  def apply(%__MODULE__{applied_award_ids: applied} = state, %PlayerXpAwarded{
        new_total: new_total,
        award_id: award_id
      }) do
    %__MODULE__{state | xp: new_total, applied_award_ids: MapSet.put(applied, award_id)}
  end

  def apply(%__MODULE__{} = state, %PlayerLeveledUp{to_level: to_level}) do
    %__MODULE__{state | level: to_level}
  end

  # Abilities survive the event store as a JSON object, so they come back with
  # string keys. Same treatment discovered_room_ids gets on the way in.
  defp normalize_abilities(abilities) do
    Map.new(~w(str dex con int wis cha)a, fn key ->
      {key, abilities[key] || Map.fetch!(abilities, Atom.to_string(key))}
    end)
  end
end

# Snapshot serialization for the Player aggregate (issue #6).
# `discovered_room_ids` is a `MapSet`; we render it as a list on serialize
# and rebuild the MapSet on deserialize via
# `Commanded.Serialization.JsonDecoder`. The custom EventStore serializer
# (`AgenticRealms.EventStore.Serializer`) and the Commanded JsonSerializer
# both invoke that protocol after `struct/2`.
defimpl Jason.Encoder, for: AgenticRealms.World.Player do
  def encode(%AgenticRealms.World.Player{} = player, opts) do
    player
    |> Map.from_struct()
    |> Map.update!(:discovered_room_ids, &MapSet.to_list/1)
    |> Map.update!(:applied_award_ids, &MapSet.to_list/1)
    |> Jason.Encode.map(opts)
  end
end

defimpl Commanded.Serialization.JsonDecoder, for: AgenticRealms.World.Player do
  def decode(%AgenticRealms.World.Player{} = state) do
    %{
      state
      | discovered_room_ids: to_set(state.discovered_room_ids),
        applied_award_ids: to_set(state.applied_award_ids)
    }
  end

  defp to_set(%MapSet{} = set), do: set
  defp to_set(ids) when is_list(ids), do: MapSet.new(ids)
  defp to_set(_), do: MapSet.new()
end
