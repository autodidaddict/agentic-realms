defmodule AgenticRealms.World.Commands.FinalizeQuest do
  @enforce_keys [
    :quest_id,
    :consumed_object_ids,
    :reward_object_id,
    :reward_name,
    :reward_description,
    :remaining_quest_object_ids,
    :completed_at
  ]
  defstruct [
    :quest_id,
    :consumed_object_ids,
    :reward_object_id,
    :reward_name,
    :reward_description,
    :remaining_quest_object_ids,
    :completed_at,
    # Feature 019 — experience reward granted on completion (0 when unauthored).
    reward_xp: 0
  ]
end
