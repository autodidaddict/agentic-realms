defmodule Srd do
  @moduledoc """
  Tabletop RPG rules resolution modeled on the SRD 5.2.

  Three layers fit together: `Srd.Content` loads SRD items and data, `Srd.Dice`
  rolls, and `Srd.Rules` resolves a completed roll into an outcome.

  ## Building a character

  `Srd.Content` answers what a character may be and what may be chosen at each
  point. It holds no character of its own: you pass in what you know and get
  back the options.

  ```elixir
  alias Srd.Content.{Classes, Subclasses, Species, Backgrounds, Feats, Feature}

  fighter = Classes.get("fighter")
  fighter.hit_die        #=> %Srd.Dice.Expr{count: 1, sides: 10}
  fighter.skill_choice   #=> %Choice{kind: :skill, choose: 2, from: [:acrobatics, ...]}

  # Subclasses are reached through the class that owns them.
  Subclasses.for_class(fighter)     #=> [%Subclass{slug: "champion", ...}]
  fighter.subclass_level            #=> 3

  # The 2024 rules have species, not races. Where a species offers a further
  # choice it is a trait of that species, and empty for the ones without.
  Species.get("elf").lineage_trait  #=> "Elven Lineage"
  Species.get("elf").lineages       #=> [%Lineage{slug: "drow"}, ...]
  Species.get("orc").lineages       #=> []

  # A background carries its ability scores, origin feat, skills, tool, and gear.
  Backgrounds.get("soldier").origin_feat  #=> "savage-attacker"

  # Feats are the one thing whose availability depends on the character, so
  # eligibility takes the facts you pass it.
  Feats.eligible(level: 4, abilities: %{str: 15}, features: [:fighting_style])

  # What a character has so far.
  Feature.through_level(fighter.features, 3)
  ```

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
