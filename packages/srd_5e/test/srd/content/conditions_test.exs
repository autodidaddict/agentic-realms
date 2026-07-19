defmodule Srd.Content.ConditionsTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Condition
  alias Srd.Content.Conditions

  describe "all/0" do
    test "returns every condition as a struct" do
      conditions = Conditions.all()
      assert length(conditions) == 15
      assert Enum.all?(conditions, &match?(%Condition{}, &1))
    end

    test "every condition has at least one effect statement" do
      assert Enum.all?(Conditions.all(), &(is_list(&1.effects) and &1.effects != []))
    end
  end

  describe "get/1" do
    test "looks up a condition by slug" do
      blinded = Conditions.get("blinded")
      assert blinded.name == "Blinded"
      assert Enum.any?(blinded.effects, &(&1 =~ ~r/can't see/i))
    end

    test "carries the reworked 2024 exhaustion levels" do
      exhaustion = Conditions.get("exhaustion")
      assert Enum.any?(exhaustion.effects, &(&1 =~ ~r/exhaustion level/i))
      assert Enum.any?(exhaustion.effects, &(&1 =~ ~r/reaches 6/i))
    end

    test "returns nil for an unknown slug" do
      assert Conditions.get("hangry") == nil
    end
  end

  describe "fetch!/1" do
    test "raises for an unknown slug" do
      assert_raise KeyError, fn -> Conditions.fetch!("hangry") end
    end
  end
end
