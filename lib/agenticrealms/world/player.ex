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
