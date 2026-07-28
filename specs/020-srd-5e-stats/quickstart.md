# Quickstart: SRD 5e Character Stats

**Feature**: 020-srd-5e-stats

How to run the feature and see each of its three stories working.

## Setup

The package is new to the app's dependency list, and the read model gains columns.

```sh
mix deps.get          # picks up the srd_5e path dependency
mix ecto.migrate      # adds the character columns, drops player mana
mix run priv/repo/seeds.exs   # reseeds; the orchard quest is now worth 300 xp
mix phx.server
```

Existing characters do not need anything done to them. The first time each one mounts, `ensure_character/1` fills in their species, class, background, scores, and proficiencies (FR-027).

## Story 1 — read a real character sheet

Log in and open the Character card in the sidebar, or click its expand control.

**Main tab** (selected on open) shows a Human Fighter with a Soldier background: AC 11, initiative +1, proficiency +2, speed 30 ft., Medium, hit dice 1d10, passive perception 12. Two bars, Health 12/12 and Experience 0/300, with `300 xp to level 2` beneath.

**Abilities tab** shows STR 17 (+3), DEX 13 (+1), CON 15 (+2), INT 12 (+1), WIS 10 (+0), CHA 8 (−1); saves with STR +5 and CON +4 marked proficient; and all eighteen skills, with Acrobatics +3, Athletics +5, History +3, Intimidation +1, and Perception +2 marked proficient.

**Spells tab** reads "Spellcasting is not yet available."

Switching tabs does not hit the server. Escape closes the sheet from any tab, and reopening lands on Main.

There is no mana bar anywhere, on the sheet or the sidebar.

## Story 2 — a new character is complete on arrival

Register a fresh account and enter the world. No prompt, no form. Open the sheet: it is the character above, identical to every other new character, because generation is deterministic.

To confirm nothing is hardcoded, change the default in `config/config.exs`:

```elixir
config :agenticrealms, :character_defaults, class: "wizard"
```

Register another account. The new character has a d6 hit die, INT as its primary ability, and a different HP, AC, and proficiency spread. Existing characters are unaffected — their `CharacterCreated` event already recorded what they were made as.

## Story 3 — derived values follow the level

Complete the orchard quest. It is now worth 300 XP, which is exactly level 2.

Watch the log for the XP and level-up notices, and the open sheet update in place:

- level 1 → 2, Experience bar resets against the 600 to level 3;
- maximum hitpoints 12 → 20 (d10: 10 at level 1, +8 at level 2 with CON +2);
- hit dice 1d10 → 2d10.

Proficiency bonus stays +2 until level 5. To see it move, award XP directly in IEx:

```elixir
alias AgenticRealms.World.Commands
Commands.award_xp(player_id, 6_500, "manual-#{System.unique_integer()}")
```

At level 5 the sheet shows proficiency +3, Athletics +6, and STR save +6, without the sheet being reopened.

To see the cap, award past 355,000. The level stops at 20, the experience caption reads `Fully levelled`, and the bar renders full while the XP total keeps climbing.

## Examine still hides everything

With another player or an NPC in the room:

```
examine the orchard keeper
```

You get a health sentence and a relative-power phrase and nothing else. No score, modifier, AC, hitpoint count, level, or XP total appears (FR-025). Examine was not changed by this feature.

## Checks

```sh
cd packages/srd_5e && mix test    # Experience and Hitpoints additions
cd - && mix precommit             # warnings-as-errors, format, full suite
```
