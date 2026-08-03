defmodule AgenticRealms.World.Commands.OpenTransientEntryExit do
  @moduledoc """
  Open the owner-only `:rift` entry exit from a permanent
  `source_room_id` into the transient region's `origin_room_id`. Sourced from
  the Region stream (not the permanent room's stream) so its history vanishes
  when the region is hard-purged. `visible_to_user_id` scopes it to the owner.
  """
  @enforce_keys [:region_id, :source_room_id, :direction, :origin_room_id, :provision_owner_id]
  defstruct [:region_id, :source_room_id, :direction, :origin_room_id, :provision_owner_id]
end
