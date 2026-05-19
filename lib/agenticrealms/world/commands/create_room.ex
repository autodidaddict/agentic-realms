defmodule AgenticRealms.World.Commands.CreateRoom do
  @enforce_keys [:room_id, :name, :description]
  defstruct [:room_id, :name, :description]
end
