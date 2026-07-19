defmodule Srd.CombatTest do
  use ExUnit.Case, async: true

  # Walks the combat round from the `Srd` moduledoc so the example can't rot.

  alias Srd.Content.{Armors, Weapons}
  alias Srd.Dice
  alias Srd.Rules.{Attack, Damage, DeathSaves, Hitpoints, Initiative}

  test "a combat round resolves through content, dice, and rules" do
    order =
      Initiative.order([
        {"knight", Dice.Rolls.initiative(2)},
        {"orc", Dice.Rolls.initiative(1)}
      ])

    assert length(order) == 2

    longsword = Weapons.get("longsword")
    orc_ac = Armors.get("chain-mail").base_ac
    assert orc_ac == 16

    result = Attack.resolve(Dice.Rolls.attack(5), target_ac: orc_ac)
    assert is_boolean(result.hit?)

    dealt = Damage.resolve(Dice.roll(longsword.damage), longsword.damage_type)
    assert dealt.type == :slashing
    assert dealt.final in 1..8

    orc = Hitpoints.new(15, 15) |> Hitpoints.damage(dealt.final)
    assert orc.hp in 7..14
    assert orc.outcome == :ok
  end

  test "dropping to 0 routes into death saves" do
    down = Hitpoints.new(4, 15) |> Hitpoints.damage(4)
    assert down.outcome == :downed

    saves = DeathSaves.new() |> DeathSaves.record_save(Dice.Rolls.death_save())
    assert saves.status in [:dying, :stable, :dead, :revived]
  end
end
