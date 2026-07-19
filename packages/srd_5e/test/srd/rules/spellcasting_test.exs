defmodule Srd.Rules.SpellcastingTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Spellcasting

  describe "save_dc/2" do
    test "is 8 + proficiency + spellcasting ability modifier" do
      assert Spellcasting.save_dc(3, 4) == 15
    end
  end

  describe "attack_bonus/2" do
    test "is proficiency + spellcasting ability modifier" do
      assert Spellcasting.attack_bonus(3, 4) == 7
    end
  end
end
