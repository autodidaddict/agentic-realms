defmodule Srd.Rules.InitiativeTest do
  use ExUnit.Case, async: true

  alias Srd.Dice.Roll
  alias Srd.Rules.Initiative

  # A d20 initiative roll with the given total.
  defp d20(total) do
    %Roll{count: 1, sides: 20, modifier: 0, dice: [total], reduce: :sum, total: total}
  end

  defp ids(order), do: Enum.map(order, &elem(&1, 0))

  describe "order/1" do
    test "orders combatants from highest initiative to lowest" do
      order = Initiative.order([{"orc", d20(12)}, {"hero", d20(19)}, {"goblin", d20(7)}])
      assert ids(order) == ["hero", "orc", "goblin"]
    end

    test "keeps input order for ties" do
      order = Initiative.order([{"a", d20(15)}, {"b", d20(15)}, {"c", d20(20)}])
      assert ids(order) == ["c", "a", "b"]
    end

    test "orders a single combatant" do
      entry = {"solo", d20(10)}
      assert Initiative.order([entry]) == [entry]
    end

    test "returns an empty list unchanged" do
      assert Initiative.order([]) == []
    end
  end
end
