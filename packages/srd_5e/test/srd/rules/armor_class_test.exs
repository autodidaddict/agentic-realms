defmodule Srd.Rules.ArmorClassTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Armors
  alias Srd.Rules.ArmorClass

  describe "compute/3" do
    test "unarmored is 10 plus the Dexterity modifier" do
      assert ArmorClass.compute(nil, 3) == 13
      assert ArmorClass.compute(nil, -1) == 9
    end

    test "light armor adds the full Dexterity modifier" do
      leather = Armors.get("leather")
      assert ArmorClass.compute(leather, 3) == 14
      assert ArmorClass.compute(leather, 0) == 11
    end

    test "medium armor caps the Dexterity modifier at +2" do
      half_plate = Armors.get("half-plate")
      assert ArmorClass.compute(half_plate, 3) == 17
      assert ArmorClass.compute(half_plate, 1) == 16
      assert ArmorClass.compute(half_plate, -1) == 14
    end

    test "heavy armor ignores Dexterity" do
      plate = Armors.get("plate")
      assert ArmorClass.compute(plate, 3) == 18
      assert ArmorClass.compute(plate, -2) == 18
    end

    test "a shield adds its bonus" do
      chain = Armors.get("chain-mail")
      shield = Armors.get("shield")
      assert ArmorClass.compute(chain, 0, shield: shield) == 18
      assert ArmorClass.compute(nil, 2, shield: shield) == 14
    end

    test "rejects wearing a shield as armor" do
      shield = Armors.get("shield")

      assert_raise ArgumentError, ~r/shield/, fn -> ArmorClass.compute(shield, 2) end
    end
  end
end
