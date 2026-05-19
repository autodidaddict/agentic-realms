defmodule AgenticRealms.World.UIEvents do
  @moduledoc """
  Transient UI event structs broadcast on `Phoenix.PubSub` topics so that
  `GameLive` can passively update logs and HUDs in response to world events.

  These are NOT persisted — domain events live in
  `AgenticRealms.World.Events.*` and are appended to the event store.

  See `specs/003-persisted-world/contracts/ui_events.md`.
  """

  defmodule RoomObjectTaken do
    @enforce_keys [:room_id, :actor_id, :actor_username, :object_id, :object_name]
    defstruct [:room_id, :actor_id, :actor_username, :object_id, :object_name]
  end

  defmodule RoomObjectDropped do
    @enforce_keys [:room_id, :actor_id, :actor_username, :object_id, :object_name]
    defstruct [:room_id, :actor_id, :actor_username, :object_id, :object_name]
  end

  defmodule RoomPlayerArrived do
    @enforce_keys [:room_id, :actor_id, :actor_username]
    defstruct [:room_id, :actor_id, :actor_username, :from_direction]
  end

  defmodule RoomPlayerLeft do
    @enforce_keys [:room_id, :actor_id, :actor_username, :to_direction]
    defstruct [:room_id, :actor_id, :actor_username, :to_direction]
  end

  defmodule PlayerCurrentRoomChanged do
    @enforce_keys [:player_id, :to_room_id]
    defstruct [:player_id, :from_room_id, :to_room_id]
  end

  defmodule PlayerInventoryChanged do
    @enforce_keys [:player_id, :change, :object_id, :object_name, :object_short_description]
    defstruct [:player_id, :change, :object_id, :object_name, :object_short_description]
  end
end
