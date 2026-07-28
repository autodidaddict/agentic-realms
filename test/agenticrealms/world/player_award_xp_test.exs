defmodule AgenticRealms.World.PlayerAwardXpTest do
  @moduledoc """
  Feature 019/020 — Player aggregate AwardXp: award, level-up, idempotency, and
  the level 20 cap.

  Thresholds are the SRD 5.2 table now, not feature 019's quadratic: level 2 at
  300, level 5 at 6,500, level 20 at 355,000.
  """
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Player
  alias AgenticRealms.World.Commands.{AwardXp, CreateCharacter}

  alias AgenticRealms.World.Events.{
    CharacterCreated,
    PlayerSpawned,
    PlayerXpAwarded,
    PlayerLeveledUp
  }

  @room "room-1"

  defp create_command do
    %CreateCharacter{
      player_id: 1,
      species_slug: "human",
      class_slug: "fighter",
      background_slug: "soldier",
      size: "medium",
      abilities: %{str: 17, dex: 13, con: 15, int: 12, wis: 10, cha: 8},
      skill_proficiencies: ["athletics"],
      save_proficiencies: ["con", "str"],
      feat_slugs: ["alert"],
      max_hp: 12
    }
  end

  # A character in the world: created, then spawned.
  defp playing do
    %Player{}
    |> then(&Player.apply(&1, Player.execute(&1, create_command())))
    |> Player.apply(%PlayerSpawned{player_id: 1, room_id: @room})
  end

  defp cmd(amount, award_id \\ "quest:q1"),
    do: %AwardXp{player_id: 1, amount: amount, award_id: award_id, source: award_id}

  test "awards xp without leveling below the threshold" do
    assert %PlayerXpAwarded{amount: 50, new_total: 50, award_id: "quest:q1", player_id: 1} =
             Player.execute(playing(), cmd(50))
  end

  test "299 is still level 1 — one short of the SRD threshold" do
    assert %PlayerXpAwarded{new_total: 299} = Player.execute(playing(), cmd(299))
  end

  test "levels up when crossing a threshold" do
    assert [%PlayerXpAwarded{new_total: 300}, %PlayerLeveledUp{from_level: 1, to_level: 2}] =
             Player.execute(playing(), cmd(300))
  end

  test "a large award crosses multiple levels at once, one level-up event" do
    assert [%PlayerXpAwarded{new_total: 6_500}, %PlayerLeveledUp{from_level: 1, to_level: 5}] =
             Player.execute(playing(), cmd(6_500))
  end

  test "non-positive amounts are a no-op" do
    assert :ok = Player.execute(playing(), cmd(0))
    assert :ok = Player.execute(playing(), cmd(-25))
  end

  test "a duplicate award_id is idempotent (no event), a new one still awards" do
    state =
      Player.apply(playing(), %PlayerXpAwarded{
        player_id: 1,
        amount: 50,
        new_total: 50,
        award_id: "quest:q1"
      })

    assert :ok = Player.execute(state, cmd(50, "quest:q1"))
    # A different award_id still awards (70 stays within level 1).
    assert %PlayerXpAwarded{new_total: 70} = Player.execute(state, cmd(20, "quest:q2"))
  end

  describe "the level 20 cap (FR-029)" do
    defp at_level_20 do
      playing()
      |> Player.apply(%PlayerXpAwarded{
        player_id: 1,
        amount: 355_000,
        new_total: 355_000,
        award_id: "seed"
      })
      |> Player.apply(%PlayerLeveledUp{player_id: 1, from_level: 1, to_level: 20})
    end

    test "experience past the last threshold is still recorded" do
      assert %PlayerXpAwarded{new_total: 405_000} =
               Player.execute(at_level_20(), cmd(50_000, "quest:beyond"))
    end

    test "no level-up is emitted past level 20" do
      result = Player.execute(at_level_20(), cmd(1_000_000, "quest:vast"))

      refute is_list(result)
      assert %PlayerXpAwarded{} = result
    end

    test "the level stays at 20 after applying the award" do
      state = at_level_20()
      state = Player.apply(state, Player.execute(state, cmd(50_000, "quest:beyond")))

      assert state.level == 20
      assert state.xp == 405_000
    end
  end

  describe "apply/2" do
    test "PlayerXpAwarded sets xp and records the award_id" do
      state =
        Player.apply(playing(), %PlayerXpAwarded{
          player_id: 1,
          amount: 50,
          new_total: 50,
          award_id: "quest:q1"
        })

      assert state.xp == 50
      assert MapSet.member?(state.applied_award_ids, "quest:q1")
    end

    test "PlayerLeveledUp sets level only — nothing else on the aggregate moves" do
      state = Player.apply(playing(), %PlayerLeveledUp{player_id: 1, from_level: 1, to_level: 3})

      assert state.level == 3
      # max_hp is the creation value; the sheet derives the real maximum from
      # class, level and Constitution on read.
      assert state.max_hp == 12
      assert state.str == 17
    end

    test "rehydration from the event stream reproduces the character, xp and level" do
      events = [
        Player.execute(%Player{}, create_command()),
        %PlayerSpawned{player_id: 1, room_id: @room},
        %PlayerXpAwarded{player_id: 1, amount: 300, new_total: 300, award_id: "quest:q1"},
        %PlayerLeveledUp{player_id: 1, from_level: 1, to_level: 2}
      ]

      state = Enum.reduce(events, %Player{}, &Player.apply(&2, &1))

      assert %CharacterCreated{} = hd(events)
      assert state.species_slug == "human"
      assert state.xp == 300
      assert state.level == 2
      assert MapSet.member?(state.applied_award_ids, "quest:q1")
    end
  end
end
