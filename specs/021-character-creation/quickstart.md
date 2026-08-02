# Quickstart: Interactive Character Creation

**Feature**: 021-character-creation | **Plan**: [plan.md](./plan.md)

How to run this, see all five stories, and prove the three things that are easy to get wrong: that a
taken name is refused, that abandoning leaves nothing, and that the username is gone.

---

## Setup

The event shape changes and the read model gains columns. The event log is destroyable in the
current phase, so purge and restage rather than migrating:

```sh
mix world.reset          # drops and recreates both databases
mix ecto.migrate         # the character_name / lineage_slug / choices migration
```

Then run both suites:

```sh
cd packages/srd_5e && mix test && cd -
mix precommit
```

The integration tests are excluded by default, as they are today:

```sh
mix test --include integration test/agenticrealms_web/live/character_creation_dialog_test.exs
```

Start the server:

```sh
mix phx.server
```

---

## Story 1 — Name and identity

1. Register a new account at `/register` with a username you will recognize, say `kevintest`.
2. Click Play.

The character creation dialog opens. There is no room behind it, no close button, and Escape does
nothing — a character comes first.

3. Type a name. Notice the availability hint settle after you stop typing.
4. Pick a species. Read its size, speed, and traits; all of it comes from `Srd.Content.Species`.
5. Pick a class. Read its hit die, primary ability, saves, and level 1 features. Note the line
   saying its subclass arrives at level 3 — it is stated, not offered.
6. Pick a background. Read the abilities it can raise, the skills it grants, and its origin feat.
7. Confirm.

You land in the starting room. Open the character sheet: it shows the name you typed, not
`kevintest`.

**Prove the identity change**: open a second browser, register a second account, create a character
with a different name, and walk it into the same room. Each sees the other's *character* name in
the room listing, in `say`, in `emote`, and in the Present card. Neither username appears anywhere.
`tell <character name> hello` works; `tell kevintest hello` does not find anyone.

---

## Story 2 — Ability scores

On the Abilities step:

1. Assign the standard array. Drop 15 on Strength, then drop 15 on Dexterity — the two swap rather
   than leaving Strength empty or 15 used twice.
2. Choose the spread. Only the three abilities your background names are offered.
3. Take `+2 / +1` and place them. Watch each ability's final score and modifier move, including the
   increase.
4. Go back to Identity and change the background. Return: the spread is cleared and re-asked
   against the new background's abilities, and the array assignment is untouched.

---

## Story 3 — Skills

On the Skills step:

1. The skills your background grants are shown as already held, and cannot be picked.
2. You get exactly as many picks as your class allows, from exactly its list.
3. Each option shows the modifier you would have, so the good picks are visible.
4. Go back and change the class. Return: the picks are cleared and re-asked against the new class'
   list, and the name, species, and background survive.

---

## Story 4 — Specializations

Create these three characters to see the generic step behave three different ways:

| Character | What the step asks |
|---|---|
| **Elf fighter, soldier** | Elven Lineage; Keen Senses' skill; Fighting Style; three Weapon Masteries; the soldier's gaming set |
| **Dwarf wizard, sage** | nothing — the step says so and asks no question |
| **Human cleric, acolyte** | size (small or medium); Skillful's skill; Versatile's origin feat; Divine Order |

The background matters as much as the species and class: a soldier's gaming set
is a real choice and appears here, while an acolyte's and a sage's tools are
settled and do not. That is the same `Choice.fixed?/1` rule that makes a dwarf
ask for no lineage.

Nothing in the dialog names a fighting style, a lineage, or a Divine Order. All three come from
`Srd.Character.choices/1`, which is why the dwarf wizard's step disappears with no special case.

**Prove FR-009**: add a lineage to `packages/srd_5e/priv/data/species.exs` for a species that has
none — give the orc two — and recompile. It appears in creation with no change to any game code:

```elixir
Draft.new()
|> Draft.put_selection(:species, "orc")
|> Draft.put_selection(:class, "wizard")
|> Draft.open_choices()
|> Enum.map(& &1.key)
#=> [:species_lineage, :class_skills]     # was [:class_skills]
```

Revert it afterwards.

---

## Story 5 — Review

1. Reach the Review step and read the whole character.
2. Go back, change the class, return. The hit die, hitpoints, saving throws, and class features all
   follow.
3. Compare against the character sheet after confirming: they match, and not by coincidence.
   `AgenticRealms.World.Stats.sheet/3` is the single adapter over
   `Srd.Character.derive/1`, and both the review and the sheet go through it, rendered by the same
   `main_panel` and `abilities_panel` components. FR-029 holds by construction rather than by two
   renderings agreeing.

---

## The three things worth proving

### A taken name is refused

Create a character named `Gandalf`. Then register a second account and try `gandalf` — refused as
taken, with every other choice still in the dialog. Case does not matter.

The check is exactly that: a check. Two players confirming the same free name in the same
millisecond can both succeed, which FR-013 permits — see research R2 for why the machinery that
would prevent it was built, measured, and removed. If you want to see the window, it is between
`PlayerNames.taken?/1` and the projection of `CharacterCreated`, and you will not hit it by hand.

### Abandoning leaves nothing

1. Register an account, click Play, fill in the whole dialog, and stop at the Review.
2. Close the tab without confirming.
3. `Repo.get(AgenticRealms.World.Schemas.PlayerState, player_id)` returns `nil`.
4. Log back in and click Play. The dialog starts over from the beginning, empty.

### Two tabs, one character

1. As a player with no character, open `/play` in two tabs. Both show the dialog.
2. Confirm in the first.
3. Confirm in the second. It does not create a second character; the player enters the world.

---

## What you should not see

- No mana, anywhere (feature 020 removed it and this feature does not bring it back).
- No equipment step. FR-033 excludes it deliberately; characters start carrying nothing.
- No subclass question at level 1, on any of the twelve classes.
- No account username rendered to any other player, in any surface.
