defmodule AgenticRealms.World.Events.QuestRewardMinted do
  @derive Jason.Encoder
  @enforce_keys [:quest_id, :player_id, :reward_object_id, :reward_name, :reward_description]
  defstruct [
    :quest_id,
    :player_id,
    :reward_object_id,
    :reward_name,
    :reward_description,
    version: 1
  ]
end
