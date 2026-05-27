defmodule AgenticRealms.World.Commands.PlaceObject do
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
    # Feature 013 — Quests. Both nil for non-quest placements (the seed
    # path and any future wizard authoring of public objects). Both set
    # by the projector's QuestAccepted handler when spawning quest-scoped
    # items. The Room aggregate passes both through to the
    # ObjectPlacedInRoom event verbatim.
    quest_player_id: nil,
    quest_instance_id: nil
  ]
end
