defmodule AgenticRealms.World.Events.QuestCompleted do
  @derive Jason.Encoder
  @enforce_keys [:quest_id, :player_id, :completed_at]
  defstruct [
    :quest_id,
    :player_id,
    :completed_at,
    xp: 0,
    version: 1
  ]
end
