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

  """

  @doc """
  Build the Commanded stream identity for a player aggregate.

  Player ids are integers (from `AgenticRealms.Accounts.Player.id`); Commanded
  identities must be strings.

  Phoenix.PubSub topic names use the colon-separated form and live in
  `AgenticRealmsWeb.Topics` so the two namespaces can't be confused at a
  call site (issue #8).
  """
  @spec player_stream_id(integer()) :: String.t()
  def player_stream_id(player_id) when is_integer(player_id),
    do: "player-" <> Integer.to_string(player_id)

  @doc """
  Build the Commanded stream identity for a room aggregate.

  See note on `player_stream_id/1` regarding the corresponding PubSub
  topic helper.
  """
  @spec room_stream_id(String.t()) :: String.t()
  def room_stream_id(room_id) when is_binary(room_id), do: "room-" <> room_id
end
