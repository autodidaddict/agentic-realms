defmodule AgenticRealms.World.Events.TransientEntryExitOpened do
  @moduledoc """
  Feature 017 — the owner-only entry exit was opened. Projected into a single
  `world_exits` row (`visible_to_user_id` = the owner) so movement and exit
  listing resolve it for the owner only. Lives on the Region stream so a
  region hard-purge erases it without touching the permanent source room.
  """
  @derive Jason.Encoder
  @enforce_keys [:region_id, :source_room_id, :direction, :target_room_id, :visible_to_user_id]
  defstruct [
    :region_id,
    :source_room_id,
    :direction,
    :target_room_id,
    :visible_to_user_id,
    version: 1
  ]
end
