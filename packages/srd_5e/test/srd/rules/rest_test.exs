defmodule Srd.Rules.RestTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Rest

  describe "hit_dice_regained/1" do
    test "is half the total, rounded down, with a minimum of one" do
      assert Rest.hit_dice_regained(1) == 1
      assert Rest.hit_dice_regained(2) == 1
      assert Rest.hit_dice_regained(5) == 2
      assert Rest.hit_dice_regained(20) == 10
    end
  end

  describe "hit_die_healing/2" do
    test "is the die roll plus the Constitution modifier" do
      assert Rest.hit_die_healing(5, 2) == 7
    end

    test "is at least 0" do
      assert Rest.hit_die_healing(1, -3) == 0
    end
  end
end
