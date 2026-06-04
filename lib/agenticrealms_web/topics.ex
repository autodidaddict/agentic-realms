defmodule AgenticRealmsWeb.Topics do
  @moduledoc """
  Phoenix.PubSub topic names for the world.

  Lives in the `AgenticRealmsWeb` namespace because PubSub topics are a
  web-tier concern — the broadcasters and `GameLive` subscribers are the
  things that need them. Kept deliberately separate from the Commanded
  stream id helpers in `AgenticRealms.World` (`player_stream_id/1`,
  `room_stream_id/1`) so a call site can't confuse the two: a Commanded
  stream id (`"player-7"`, `"room-uuid"`) and a PubSub topic
  (`"player:7"`, `"room:uuid"`) differ only by one punctuation character,
  and we've already shipped one bug from that mix-up (issue #8).
  """

  @doc """
  Build the Phoenix.PubSub topic name for a room (carries
  `RoomObjectTaken`, `RoomObjectDropped`, `RoomPlayerArrived`,
  `RoomPlayerLeft`, and `RoomUtterance`).
  """
  @spec room_topic(String.t()) :: String.t()
  def room_topic(room_id) when is_binary(room_id), do: "room:" <> room_id

  @doc """
  Build the Phoenix.PubSub topic name for a player (carries
  `PlayerCurrentRoomChanged`, `PlayerInventoryChanged`,
  `PrivateUtterance`, and `ChatUtterance`).
  """
  @spec player_topic(integer()) :: String.t()
  def player_topic(player_id) when is_integer(player_id),
    do: "player:" <> Integer.to_string(player_id)

  @doc """
  Feature 014 US6 — global topic for Object Blueprint registry change
  events (`WizardBlueprintRegistryChanged`). Every wizard LiveView
  subscribes on mount so that all open registries patch in place when
  any wizard creates or edits a Blueprint anywhere in the world.
  """
  @spec blueprints_topic() :: String.t()
  def blueprints_topic, do: "blueprints"
end
