defmodule Srd do
  @moduledoc """
  Tabletop RPG rules resolution modeled on the SRD 5.2.

  Three layers fit together: `Srd.Content` loads SRD items and data, `Srd.Dice`
  rolls, and `Srd.Rules` resolves a completed roll into an outcome.

  ## A combat round

  ```elixir
  alias Srd.Content.{Weapons, Armors}
  alias Srd.Dice
  alias Srd.Rules.{Initiative, Attack, Damage, Hitpoints, DeathSaves}

  # Order the combatants. The caller rolls each initiative and captures the roll.
  Initiative.order([
    {"knight", Dice.Rolls.initiative(2)},
    {"orc", Dice.Rolls.initiative(1)}
  ])
  #=> [{"orc", %Srd.Dice.Roll{...}}, {"knight", %Srd.Dice.Roll{...}}]   # highest first

  # The knight attacks the orc with a longsword, against its chain-mail AC.
  longsword = Weapons.get("longsword")          # 1d8 slashing, versatile 1d10
  orc_ac = Armors.get("chain-mail").base_ac     # 16

  attack = Dice.Rolls.attack(5)                 # 1d20 + attack bonus
  result = Attack.resolve(attack, target_ac: orc_ac)
  #=> %Srd.Rules.Attack{hit?: true, critical?: false, natural: 14, total: 19, target_ac: 16}

  # On a hit, roll the weapon's damage (parsed from content) and apply defenses.
  if result.hit? do
    damage = Dice.roll(longsword.damage)
    dealt = Damage.resolve(damage, longsword.damage_type)
    #=> %Srd.Rules.Damage{type: :slashing, raw: 4, final: 4}

    # Apply to the orc's hit points. The outcome drives what happens next.
    Hitpoints.new(15, 15) |> Hitpoints.damage(dealt.final)
    #=> %Srd.Rules.Hitpoints{hp: 11, max_hp: 15, temp_hp: 0, outcome: :ok}
  end
  ```

  When `Hitpoints` reports `:downed`, the caller starts death saves; a hit taken
  while at 0 hit points is a failure it routes in.

  ```elixir
  down = Hitpoints.new(4, 15) |> Hitpoints.damage(4)
  down.outcome
  #=> :downed

  DeathSaves.new() |> DeathSaves.record_save(Dice.Rolls.death_save())
  #=> %Srd.Rules.DeathSaves{successes: 1, failures: 0, status: :dying}
  ```
  """
end
