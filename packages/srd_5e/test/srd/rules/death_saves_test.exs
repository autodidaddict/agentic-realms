defmodule Srd.Rules.DeathSavesTest do
  use ExUnit.Case, async: true

  alias Srd.Dice.Roll
  alias Srd.Rules.DeathSaves

  # A straight d20 showing `nat` (death saves take no modifier).
  defp d20(nat) do
    %Roll{count: 1, sides: 20, modifier: 0, dice: [nat], reduce: :sum, total: nat}
  end

  test "new/0 starts dying with an empty tally" do
    assert DeathSaves.new() == %DeathSaves{successes: 0, failures: 0, status: :dying}
  end

  describe "record_save/2" do
    test "a total of exactly 10 is a success" do
      state = DeathSaves.record_save(DeathSaves.new(), d20(10))
      assert state.successes == 1
      assert state.status == :dying
    end

    test "a total of 9 is a failure" do
      state = DeathSaves.record_save(DeathSaves.new(), d20(9))
      assert state.failures == 1
      assert state.status == :dying
    end

    test "a natural 1 adds two failures" do
      state = DeathSaves.record_save(DeathSaves.new(), d20(1))
      assert state.failures == 2
      assert state.status == :dying
    end

    test "a natural 20 revives" do
      state = DeathSaves.record_save(DeathSaves.new(), d20(20))
      assert state.status == :revived
    end

    test "three successes stabilizes" do
      state =
        DeathSaves.new()
        |> DeathSaves.record_save(d20(10))
        |> DeathSaves.record_save(d20(15))
        |> DeathSaves.record_save(d20(12))

      assert state.successes == 3
      assert state.status == :stable
    end

    test "three failures is death" do
      state =
        DeathSaves.new()
        |> DeathSaves.record_save(d20(5))
        |> DeathSaves.record_save(d20(9))
        |> DeathSaves.record_save(d20(2))

      assert state.failures == 3
      assert state.status == :dead
    end

    test "a natural 1 can kill from a single prior failure" do
      state =
        DeathSaves.new()
        |> DeathSaves.record_save(d20(3))
        |> DeathSaves.record_save(d20(1))

      assert state.failures == 3
      assert state.status == :dead
    end

    test "interleaving successes and failures still settles by count" do
      state =
        DeathSaves.new()
        |> DeathSaves.record_save(d20(15))
        |> DeathSaves.record_save(d20(4))
        |> DeathSaves.record_save(d20(12))
        |> DeathSaves.record_damage()
        |> DeathSaves.record_save(d20(18))

      assert state.successes == 3
      assert state.failures == 2
      assert state.status == :stable
    end

    test "raises on a non-d20 roll" do
      d6 = %Roll{count: 1, sides: 6, modifier: 0, dice: [4], reduce: :sum, total: 4}

      assert_raise ArgumentError, ~r/d20 test requires a d20 roll, got d6/, fn ->
        DeathSaves.record_save(DeathSaves.new(), d6)
      end
    end
  end

  describe "record_damage/2" do
    test "a hit at 0 HP adds a failure" do
      state = DeathSaves.record_damage(DeathSaves.new())
      assert state.failures == 1
      assert state.status == :dying
    end

    test "a critical hit at 0 HP adds two failures" do
      state = DeathSaves.record_damage(DeathSaves.new(), critical?: true)
      assert state.failures == 2
    end

    test "hits can kill" do
      state =
        DeathSaves.new()
        |> DeathSaves.record_damage()
        |> DeathSaves.record_damage(critical?: true)

      assert state.failures == 3
      assert state.status == :dead
    end
  end

  describe "settled sequences" do
    test "further saves and hits are no-ops once revived" do
      revived = DeathSaves.record_save(DeathSaves.new(), d20(20))

      assert DeathSaves.record_save(revived, d20(2)) == revived
      assert DeathSaves.record_damage(revived, critical?: true) == revived
    end

    test "further saves and hits are no-ops once dead" do
      dead =
        DeathSaves.new()
        |> DeathSaves.record_save(d20(5))
        |> DeathSaves.record_save(d20(6))
        |> DeathSaves.record_save(d20(7))

      assert dead.status == :dead
      assert DeathSaves.record_save(dead, d20(20)) == dead
      assert DeathSaves.record_damage(dead) == dead
    end
  end
end
