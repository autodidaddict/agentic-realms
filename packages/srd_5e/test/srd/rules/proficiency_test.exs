defmodule Srd.Rules.ProficiencyTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Proficiency

  describe "bonus/1" do
    test "is +2 at low levels and rises by 1 every four levels" do
      assert Proficiency.bonus(1) == 2
      assert Proficiency.bonus(4) == 2
      assert Proficiency.bonus(5) == 3
      assert Proficiency.bonus(8) == 3
      assert Proficiency.bonus(9) == 4
      assert Proficiency.bonus(13) == 5
      assert Proficiency.bonus(17) == 6
      assert Proficiency.bonus(20) == 6
    end
  end

  describe "bonus_for_cr/1" do
    test "is +2 through CR 4, including fractional CRs" do
      assert Proficiency.bonus_for_cr(0) == 2
      assert Proficiency.bonus_for_cr(0.5) == 2
      assert Proficiency.bonus_for_cr(4) == 2
    end

    test "rises by 1 every four CR above 4" do
      assert Proficiency.bonus_for_cr(5) == 3
      assert Proficiency.bonus_for_cr(9) == 4
      assert Proficiency.bonus_for_cr(21) == 7
      assert Proficiency.bonus_for_cr(30) == 9
    end
  end
end
