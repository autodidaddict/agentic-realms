defmodule AgenticRealms.World.Events.ObjectPlacedInRoom do
  @derive Jason.Encoder
  @enforce_keys [
    :room_id,
    :object_id,
    :name,
    :short_description,
    :long_description,
    :fixed
  ]
  defstruct [
    :room_id,
    :object_id,
    :name,
    :short_description,
    :long_description,
    :fixed,
    behaviors: [],
    # Feature 013 — Quests. Both nil for legacy events and non-quest
    # placements. Both set for quest-scoped spawns. The WorldProjector's
    # handler reads with Map.get(.., nil) so legacy events without these
    # keys at all still replay cleanly.
    quest_player_id: nil,
    quest_instance_id: nil,
    version: 1
  ]
end
