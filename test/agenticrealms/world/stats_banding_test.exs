defmodule AgenticRealms.World.StatsBandingTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Stats

  describe "health_tier/2" do
    test "full health is Very healthy" do
      assert {:very_healthy, "Very healthy"} = Stats.health_tier(10, 10)
      assert {:very_healthy, "Very healthy"} = Stats.health_tier(9, 10)
    end

    test "bands map to the right tier" do
      assert {:healthy, "Healthy"} = Stats.health_tier(80, 100)
      assert {:healthy, "Healthy"} = Stats.health_tier(65, 100)
      assert {:weakened, "Weakened"} = Stats.health_tier(64, 100)
      assert {:weakened, "Weakened"} = Stats.health_tier(35, 100)
      assert {:very_weakened, "Very Weakened"} = Stats.health_tier(34, 100)
      assert {:very_weakened, "Very Weakened"} = Stats.health_tier(10, 100)
      assert {:deaths_door, "At death's door"} = Stats.health_tier(9, 100)
    end

    test "zero HP is At death's door" do
      assert {:deaths_door, "At death's door"} = Stats.health_tier(0, 10)
    end

    test "guards against a zero/negative max" do
      assert {:deaths_door, "At death's door"} = Stats.health_tier(5, 0)
    end
  end

  describe "relative_power/2" do
    test "same or near level is 'about as powerful'" do
      assert "about as powerful" == Stats.relative_power(5, 5)
      assert "about as powerful" == Stats.relative_power(5, 4)
      assert "about as powerful" == Stats.relative_power(5, 6)
    end

    test "tightened +/-4 extremes" do
      assert "weaker" == Stats.relative_power(5, 3)
      assert "Much weaker" == Stats.relative_power(5, 1)
      assert "more powerful" == Stats.relative_power(5, 7)
      assert "more powerful" == Stats.relative_power(5, 8)
      assert "too powerful to even compare" == Stats.relative_power(5, 9)
    end
  end
end
