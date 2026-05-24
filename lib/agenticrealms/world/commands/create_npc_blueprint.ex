defmodule AgenticRealms.World.Commands.CreateNPCBlueprint do
  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [:blueprint_id, :name, :short_description, :long_description]
end
