defmodule AgenticRealms.World.Events.QuestCompleted do
  @derive Jason.Encoder
  @enforce_keys [:quest_id, :player_id, :completed_at]
  defstruct [
    :quest_id,
    :player_id,
    :completed_at,
    # Feature 019 — denormalized experience reward for this completion (0 when
    # unauthored). Read by World.Progression.XpAwarder to award XP.
    xp: 0,
    version: 1
  ]
end
