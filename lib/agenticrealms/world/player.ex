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
            discovered_room_ids: MapSet.new()

  alias AgenticRealms.World.Commands.{SpawnPlayer, MovePlayer, RecordRoomDiscovery}
  alias AgenticRealms.World.Events.{PlayerSpawned, PlayerMoved, PlayerDiscoveredRoom}

  # --- SpawnPlayer --------------------------------------------------------

  @spec execute(%__MODULE__{}, %SpawnPlayer{} | %MovePlayer{} | %RecordRoomDiscovery{}) ::
          %PlayerSpawned{} | %PlayerMoved{} | %PlayerDiscoveredRoom{} | :ok | {:error, atom()}
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

  # --- apply/2 ------------------------------------------------------------

  @spec apply(%__MODULE__{}, %PlayerSpawned{} | %PlayerMoved{} | %PlayerDiscoveredRoom{}) ::
          %__MODULE__{}
  def apply(%__MODULE__{} = state, %PlayerSpawned{player_id: pid, room_id: room_id}) do
    %__MODULE__{state | id: pid, current_room_id: room_id}
  end

  def apply(%__MODULE__{} = state, %PlayerMoved{to_room_id: to}) do
    %__MODULE__{state | current_room_id: to}
  end

  def apply(%__MODULE__{discovered_room_ids: discovered} = state, %PlayerDiscoveredRoom{
        room_id: rid
      }) do
    %__MODULE__{state | discovered_room_ids: MapSet.put(discovered, rid)}
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
    |> Jason.Encode.map(opts)
  end
end

defimpl Commanded.Serialization.JsonDecoder, for: AgenticRealms.World.Player do
  def decode(%AgenticRealms.World.Player{discovered_room_ids: ids} = state)
      when is_list(ids) do
    %{state | discovered_room_ids: MapSet.new(ids)}
  end

  def decode(%AgenticRealms.World.Player{} = state), do: state
end
