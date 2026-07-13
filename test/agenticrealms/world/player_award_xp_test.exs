defmodule AgenticRealms.World.PlayerAwardXpTest do
  @moduledoc "Feature 019 — Player aggregate AwardXp: award, level-up, idempotency."
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Player
  alias AgenticRealms.World.Commands.AwardXp
  alias AgenticRealms.World.Events.{PlayerSpawned, PlayerXpAwarded, PlayerLeveledUp}

  @room "room-1"

  defp spawned, do: Player.apply(%Player{}, %PlayerSpawned{player_id: 1, room_id: @room})

  defp cmd(amount, award_id \\ "quest:q1"),
    do: %AwardXp{player_id: 1, amount: amount, award_id: award_id, source: award_id}

  test "awards xp without leveling below the threshold" do
    assert %PlayerXpAwarded{amount: 50, new_total: 50, award_id: "quest:q1", player_id: 1} =
             Player.execute(spawned(), cmd(50))
  end

  test "levels up when crossing a threshold" do
    assert [%PlayerXpAwarded{new_total: 100}, %PlayerLeveledUp{from_level: 1, to_level: 2}] =
             Player.execute(spawned(), cmd(100))
  end

  test "a large award crosses multiple levels at once, one level-up event" do
    assert [%PlayerXpAwarded{new_total: 1000}, %PlayerLeveledUp{from_level: 1, to_level: 5}] =
             Player.execute(spawned(), cmd(1000))
  end

  test "non-positive amounts are a no-op" do
    assert :ok = Player.execute(spawned(), cmd(0))
    assert :ok = Player.execute(spawned(), cmd(-25))
  end

  test "a duplicate award_id is idempotent (no event), a new one still awards" do
    state =
      Player.apply(spawned(), %PlayerXpAwarded{
        player_id: 1,
        amount: 50,
        new_total: 50,
        award_id: "quest:q1"
      })

    assert :ok = Player.execute(state, cmd(50, "quest:q1"))
    # A different award_id still awards (70 stays within level 1).
    assert %PlayerXpAwarded{new_total: 70} = Player.execute(state, cmd(20, "quest:q2"))
  end

  describe "apply/2" do
    test "PlayerXpAwarded sets xp and records the award_id" do
      state =
        Player.apply(spawned(), %PlayerXpAwarded{
          player_id: 1,
          amount: 50,
          new_total: 50,
          award_id: "quest:q1"
        })

      assert state.xp == 50
      assert MapSet.member?(state.applied_award_ids, "quest:q1")
    end

    test "PlayerLeveledUp sets level only (no other stat growth)" do
      state = Player.apply(spawned(), %PlayerLeveledUp{player_id: 1, from_level: 1, to_level: 3})
      assert state.level == 3
      assert state.max_hp == 10
      assert state.max_mana == 10
      assert state.str == 12
    end

    test "rehydration from the event stream reproduces xp, level, and applied ids" do
      events = [
        %PlayerSpawned{player_id: 1, room_id: @room},
        %PlayerXpAwarded{player_id: 1, amount: 100, new_total: 100, award_id: "quest:q1"},
        %PlayerLeveledUp{player_id: 1, from_level: 1, to_level: 2}
      ]

      state = Enum.reduce(events, %Player{}, &Player.apply(&2, &1))

      assert state.xp == 100
      assert state.level == 2
      assert MapSet.member?(state.applied_award_ids, "quest:q1")
    end
  end
end
