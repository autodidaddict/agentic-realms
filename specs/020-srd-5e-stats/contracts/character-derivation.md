# Contract: `Srd.Character` — the derived layer

**Package**: `packages/srd_5e` | **Feature**: 020-srd-5e-stats (FR-006)

Every calculation behind a character sheet lives in the package. The game reads a row, hands the facts over, and renders what comes back. It does no SRD arithmetic of its own.

`Srd.Character` sits at the top level beside `Srd.Content`, `Srd.Dice`, and `Srd.Rules`. It is the composition layer over `Srd.Rules.*`: it holds no character, stores nothing, and reads nothing. You pass in what you know and get back what follows from it — the same contract `Srd.Content` keeps for options, applied to numbers.

## `derive(facts) :: map()`

### Input

```elixir
%{
  species:             "human",          # slug
  class:               "fighter",        # slug
  background:          "soldier",        # slug, or nil
  size:                :medium,
  level:               3,
  xp:                  1_200,
  abilities:           %{str: 17, dex: 13, con: 15, int: 12, wis: 10, cha: 8},
  skill_proficiencies: [:acrobatics, :athletics, :history, :intimidation, :perception],
  save_proficiencies:  [:str, :con],
  armor:               nil,              # Srd.Content.Armor, or nil for unarmored
  shield:              nil               # Srd.Content.Armor of category :shield, or nil
}
```

`:armor` and `:shield` are accepted now and always `nil` in this milestone, because equipment is out of scope. Taking them keeps the armor class path honest rather than hardcoding unarmored inside the derivation.

Unknown slugs raise `ArgumentError` naming the slug. A character referencing content that does not exist is a bug, not a value to default around.

### Output

```elixir
%{
  species:            %{slug: "human", name: "Human"},
  class:              %{slug: "fighter", name: "Fighter"},
  background:         %{slug: "soldier", name: "Soldier"},
  size:               :medium,
  speed:              30,
  level:              3,
  proficiency_bonus:  2,
  experience:         %{total: 1_200, into_level: 300, to_next: 1_800,
                        fraction: 0.166…, maxed?: false},
  max_hit_points:     28,
  hit_dice:           %Srd.Dice.Expr{count: 3, sides: 10, modifier: 0},
  armor_class:        11,
  initiative:         1,
  passive_perception: 12,
  abilities: [%{key: :str, name: "Strength", score: 17, modifier: 3}, …],          # 6, STR..CHA
  saves:     [%{key: :str, name: "Strength", modifier: 5, proficient?: true}, …],  # 6, STR..CHA
  skills:    [%{key: :acrobatics, name: "Acrobatics", ability: :dex,
                modifier: 3, proficient?: true}, …]                                 # 18, alphabetical
}
```

`max_hit_points` and not `hit_points`. Current hitpoints are game state — damage, healing, and death are the caller's business, and `Srd.Rules.Hitpoints` already models the pool. Derivation answers only how large the pool should be.

Ordering is part of the contract. `abilities` and `saves` come back in canonical STR, DEX, CON, INT, WIS, CHA order; `skills` alphabetically by display name. A consumer renders the lists as given and does not sort.

## Supporting primitives

`derive/1` composes these. Each is independently useful and independently tested, and the ones marked new are added by this feature.

| Function | Status | Returns |
|---|---|---|
| `Srd.Rules.Ability.modifier/1` | exists | `(score - 10) / 2`, floored |
| `Srd.Rules.Ability.all/0` | **new** | `[:str, :dex, :con, :int, :wis, :cha]` in canonical order |
| `Srd.Rules.Ability.name/1` | **new** | `:str` → `"Strength"` |
| `Srd.Rules.Ability.standard_array/0` | **new** | `[15, 14, 13, 12, 10, 8]` |
| `Srd.Rules.Proficiency.bonus/1` | exists | `2 + div(level - 1, 4)` |
| `Srd.Rules.Skill.check_modifier/3` | exists | ability modifier plus proficiency |
| `Srd.Rules.Skill.name/1` | **new** | `:sleight_of_hand` → `"Sleight of Hand"` |
| `Srd.Rules.Save.modifier/3` | **new** | ability modifier plus proficiency bonus when proficient |
| `Srd.Rules.Initiative.modifier/1` | **new** | the Dexterity modifier |
| `Srd.Rules.Check.passive/2` | exists | `10 + modifier`, used for passive perception |
| `Srd.Rules.ArmorClass.compute/3` | exists | armor, Dexterity, optional shield |
| `Srd.Rules.Hitpoints.maximum/3` | **new** | see contracts/hitpoints.md |
| `Srd.Rules.Hitpoints.hit_dice/2` | **new** | `%Expr{count: level, sides: die_sides}` |
| `Srd.Rules.Experience.progress/1` | **new** | see contracts/experience.md |

`Srd.Rules.Save.modifier/3` mirrors `Skill.check_modifier/3`'s shape — `(ability_modifier, proficiency, opts)` with `proficient?:` — so the two read alike at every call site.

`Srd.Rules.Initiative.modifier/1` is a one-line function today and deliberately so. It is the seam the Alert feat needs, which adds the proficiency bonus to initiative, and putting it in now means that feature edits the package rather than hunting for a bare `dex_mod` in the game.

## What stays in the game

The game keeps what is not an SRD rule:

- reading `player_state` and building the facts map (`World.Stats.for_player/1`);
- display concerns — sign formatting, labels, which values land on which tab;
- generation *policy* in `World.CharacterGen`: which ability gets the highest score, which skill fills Human's Skillful trait, which origin feat fills Versatile. The SRD says a character makes these choices, not what to choose. The package supplies the standard array and the background's legal spreads; picking among them is ours.

`AgenticRealms.World.Character` is **not** created. It was in an earlier draft of this plan and is dropped — it would have been exactly the arithmetic this module owns.

## Relationship to ADR-0004

ADR-0004 says the content layer "holds no character of its own: you pass in what you know and get back the options." This module extends that sentence from options to numbers, and keeps its substance: nothing is stored, no character record exists in the package, and `derive/1` is a pure function of its argument.

The ADR is still worth a short amendment noting that the package now owns the derived layer as well as the content, since a reader could fairly take the original wording to exclude it.

## Tests

`packages/srd_5e/test/srd/character_test.exs`, `async: true`:

- the level 1 default character from data-model.md §6.3, every output field asserted;
- the same character at levels 5, 9, 13, 17, and 20, checking proficiency bonus, maximum hitpoints, hit dice, and every proficient save and skill against published SRD values (SC-003);
- ordering: abilities and saves canonical, skills alphabetical, lengths 6 / 6 / 18;
- a caster class, confirming nothing in `derive/1` assumes a martial;
- armor and shield passed explicitly, confirming armor class routes through `ArmorClass.compute/3` rather than assuming unarmored;
- an unknown slug raising `ArgumentError`.

Each new primitive gets its own test in the module that owns it.
