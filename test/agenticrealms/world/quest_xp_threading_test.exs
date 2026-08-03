defmodule AgenticRealms.World.QuestXpThreadingTest do
  @moduledoc "The quest's reward xp is threaded into QuestCompleted."
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Quest
  alias AgenticRealms.World.Commands.FinalizeQuest
  alias AgenticRealms.World.Events.{QuestAccepted, QuestCompleted}

  defp active do
    Quest.apply(%Quest{}, %QuestAccepted{
      quest_id: "q1",
      player_id: 1,
      npc_blueprint_id: "bp",
      slug: "golden_apples",
      definition_snapshot: %{},
      accepted_at: ~U[2026-07-12 00:00:00Z]
    })
  end

  defp finalize(reward_xp) do
    %FinalizeQuest{
      quest_id: "q1",
      consumed_object_ids: [],
      reward_object_id: "obj",
      reward_name: "prize",
      reward_description: "d",
      remaining_quest_object_ids: [],
      completed_at: ~U[2026-07-12 00:01:00Z],
      reward_xp: reward_xp
    }
  end

  test "reward_xp is carried on the emitted QuestCompleted event" do
    events = Quest.execute(active(), finalize(100))
    assert Enum.any?(events, &match?(%QuestCompleted{xp: 100, player_id: 1}, &1))
  end

  test "an unauthored reward defaults to 0 xp" do
    events = Quest.execute(active(), finalize(0))
    assert Enum.any?(events, &match?(%QuestCompleted{xp: 0}, &1))
  end
end
