defmodule Srd.Rules.ConcentrationTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Concentration

  describe "save_dc/1" do
    test "is at least 10" do
      assert Concentration.save_dc(0) == 10
      assert Concentration.save_dc(19) == 10
    end

    test "is half the damage when that exceeds 10" do
      assert Concentration.save_dc(22) == 11
      assert Concentration.save_dc(30) == 15
    end
  end
end
