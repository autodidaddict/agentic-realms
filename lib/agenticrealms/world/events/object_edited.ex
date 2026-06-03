defmodule AgenticRealms.World.Events.ObjectEdited do
  @moduledoc """
  Feature 014 US5 — world Object edit event. Emitted by the `Room`
  aggregate on a successful `EditObject`. Projected by
  `WorldProjector` (in-place update to `world_objects`). Picked up by
  `UIEventBroadcaster` to fan out a `RoomObjectEdited` UI event.

  See `specs/014-item-blueprints/contracts/events.md`.
  """

  @derive Jason.Encoder
  @enforce_keys [:object_id, :room_id, :fields_changed]
  defstruct [:object_id, :room_id, :fields_changed, version: 1]
end
