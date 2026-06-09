defmodule AgenticRealms.World.Commands.ProvisionTransientRegion do
  @moduledoc """
  Feature 017 — provision a transient region on behalf of a provision-owner.
  Carries the generated region id + name, the owner, the provisioning
  timestamp (set by the dispatcher; the lifetime cap is measured from it),
  the permanent source room the owner provisions from, and the generated
  origin room they are placed into.
  """
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
    :origin_room_id
  ]
end
