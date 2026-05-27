defmodule AgenticRealms.World.Events.QuestItemsConsumed do
  @derive Jason.Encoder
  @enforce_keys [:quest_id, :player_id, :consumed_object_ids]
  defstruct [
    :quest_id,
    :player_id,
    :consumed_object_ids,
    version: 1
  ]
end
