defmodule AgenticRealms.World.Events.QuestItemsCleanedUp do
  @derive Jason.Encoder
  @enforce_keys [:quest_id, :remaining_quest_object_ids]
  defstruct [
    :quest_id,
    :remaining_quest_object_ids,
    version: 1
  ]
end
