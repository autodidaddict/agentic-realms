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
            # Feature 019 — Real Stats. Aggregate-owned; nil until PlayerSpawned
            # seeds the documented defaults (abilities 12, level 1, xp 0, hp/mana
            # 10/10). Plain integers — no snapshot-serialization treatment needed.
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
            mana: nil,
            max_mana: nil,
            # Feature 019 — idempotency guard. award_ids already applied, so a
            # redelivered/replayed AwardXp is a no-op. Serialized like
            # discovered_room_ids (list on the wire, MapSet in memory).
            applied_award_ids: MapSet.new()

  alias AgenticRealms.World.Commands.{SpawnPlayer, MovePlayer, RecordRoomDiscovery, AwardXp}

  alias AgenticRealms.World.Events.{
    PlayerSpawned,
    PlayerMoved,
    PlayerDiscoveredRoom,
    PlayerXpAwarded,
    PlayerLeveledUp
  }

  alias AgenticRealms.World.LevelCurve

  # --- SpawnPlayer --------------------------------------------------------

  @spec execute(
          %__MODULE__{},
          %SpawnPlayer{} | %MovePlayer{} | %RecordRoomDiscovery{} | %AwardXp{}
        ) ::
          %PlayerSpawned{}
          | %PlayerMoved{}
          | %PlayerDiscoveredRoom{}
          | %PlayerXpAwarded{}
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
        new_level = LevelCurve.level_for_xp(new_total)

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
        ) :: %__MODULE__{}
  def apply(%__MODULE__{} = state, %PlayerSpawned{player_id: pid, room_id: room_id}) do
    # Feature 019 — seed the documented starting stats on spawn.
    %__MODULE__{
      state
      | id: pid,
        current_room_id: room_id,
        str: 12,
        dex: 12,
        con: 12,
        int: 12,
        wis: 12,
        cha: 12,
        level: 1,
        xp: 0,
        hp: 10,
        max_hp: 10,
        mana: 10,
        max_mana: 10
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
