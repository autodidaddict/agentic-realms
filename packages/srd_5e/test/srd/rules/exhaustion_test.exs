defmodule Srd.Rules.ExhaustionTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Exhaustion

  describe "effect/1" do
    test "level 0 has no penalties and is not fatal" do
      effect = Exhaustion.effect(0)
      assert effect.d20_penalty == 0
      assert effect.speed_penalty == 0
      refute effect.dead?
    end

    test "penalties scale with the level" do
      effect = Exhaustion.effect(3)
      assert effect.level == 3
      assert effect.d20_penalty == -6
      assert effect.speed_penalty == -15
      refute effect.dead?
    end

    test "level 6 is fatal" do
      assert Exhaustion.effect(6).dead?
    end
  end
end
