defmodule AgenticRealms.World.RoomView do
  @moduledoc """
  Read model the LiveView consumes when rendering a `:room` log entry.
  Produced by `AgenticRealms.World.Queries.look_room/1`.
  """

  @enforce_keys [:id, :name, :description, :exits, :objects, :other_players]
  defstruct [:id, :name, :description, :exits, :objects, :other_players]
end
