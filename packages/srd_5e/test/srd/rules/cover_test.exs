defmodule Srd.Rules.CoverTest do
  use ExUnit.Case, async: true

  alias Srd.Rules.Cover

  describe "bonus/1" do
    test "grants +2 for half and +5 for three-quarters cover" do
      assert Cover.bonus(:none) == 0
      assert Cover.bonus(:half) == 2
      assert Cover.bonus(:three_quarters) == 5
    end

    test "total cover can't be targeted" do
      assert Cover.bonus(:total) == :cannot_target
    end
  end
end
