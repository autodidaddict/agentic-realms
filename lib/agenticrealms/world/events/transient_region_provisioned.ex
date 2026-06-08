defmodule AgenticRealms.World.Events.TransientRegionProvisioned do
  @moduledoc """
  Feature 017 — emitted when a transient region is provisioned. The event
  type itself is the `kind: :transient` discriminator; the projector inserts
  the `regions` row with the owner + lifetime anchor + source/origin rooms.
  """
  @derive Jason.Encoder
  @enforce_keys [
    :region_id,
    :name,
    :provision_owner_id,
    :provisioned_at,
    :source_room_id,
    :origin_room_id
  ]
  defstruct [
    :region_id,
    :name,
    :provision_owner_id,
    :provisioned_at,
    :source_room_id,
    :origin_room_id,
    version: 1
  ]
end
