defmodule AgenticRealms.World do
  @moduledoc """
  Bounded context for the persisted, interactive game world.

  Built on `Commanded` for event sourcing. Two aggregate types:

    * `AgenticRealms.World.Room` — owns a room's contents and exit set;
      serializes per-room operations like `TakeObject` / `DropObject`.
    * `AgenticRealms.World.Player` — owns a player's current room;
      emits the single `PlayerMoved` event for movement.

  Domain events live under `AgenticRealms.World.Events.*` (persisted in the
  event store). UI events live under `AgenticRealms.World.UIEvents.*` and
  are broadcast via `Phoenix.PubSub` only.

  See `specs/003-persisted-world/plan.md` for the full design.
  """

  @doc """
  Build the Commanded stream identity for a player aggregate.

  Player ids are integers (from `AgenticRealms.Accounts.Player.id`); Commanded
  identities must be strings.
  """
  @spec player_stream_id(integer()) :: String.t()
  def player_stream_id(player_id) when is_integer(player_id),
    do: "player-" <> Integer.to_string(player_id)

  @doc """
  Build the Commanded stream identity for a room aggregate.
  """
  @spec room_stream_id(String.t()) :: String.t()
  def room_stream_id(room_id) when is_binary(room_id), do: "room-" <> room_id

  @doc """
  Build the Phoenix.PubSub topic name for a room (carries `RoomObjectTaken`,
  `RoomObjectDropped`, `RoomPlayerArrived`, `RoomPlayerLeft`).

  Distinct prefix from `room_stream_id/1` because the Commanded stream id
  and the PubSub topic are different namespaces. The colon form matches
  `contracts/ui_events.md`.
  """
  @spec room_topic(String.t()) :: String.t()
  def room_topic(room_id) when is_binary(room_id), do: "room:" <> room_id

  @doc """
  Build the Phoenix.PubSub topic name for a player (carries
  `PlayerCurrentRoomChanged`, `PlayerInventoryChanged`).
  """
  @spec player_topic(integer()) :: String.t()
  def player_topic(player_id) when is_integer(player_id),
    do: "player:" <> Integer.to_string(player_id)
end
