# Contract: The Creation Dialog

**Feature**: 021-character-creation | **Component**:
`AgenticRealmsWeb.GameComponents.CharacterCreation`

The modal, its steps, what each one shows, and every interaction that reaches the server.

---

## Shape

It wraps the existing `<.modal>` shell from `Primitives`, like the four player modals do, with two
differences that FR-002 requires:

- **No close button and no backdrop dismiss.** There is no way out of the dialog except creating a
  character or leaving the page.
- **Nothing is playable behind it.** In the `:creating` phase the game pane renders inert and
  empty, because there is no world behind the dialog yet — the player has not been spawned.

The shell does not support that today. `modal/1` in
`lib/agenticrealms_web/components/game/primitives.ex` hardcodes three ways out — a
`phx-window-keydown="close_modal"` Escape binding on the backdrop, a full-bleed
`phx-click="close_modal"` div, and a `✕` button — and offers no way to suppress them. It gains one
attribute:

```elixir
attr :dismissable, :boolean, default: true
```

When `false`, all three are omitted: the keydown binding is not set, the click-catcher div is not
rendered, and the header shows no close button. The four existing modals keep the default and are
unchanged.

Suppressing them is not optional politeness. `GameLive`'s `close_modal` handler only clears the
`@modal` assign, which the creation dialog does not use, so leaving the bindings in place would
render a close button and a clickable backdrop that silently do nothing — worse than either
dismissing or not being there.

Five steps, one per user story, so a story ships by adding its step:

```
Identity ──→ Abilities ──→ Skills ──→ Specializations ──→ Review
  (P1)         (P2)          (P3)          (P4)             (P5)
```

Until a step's story ships, `CharacterGen` fills that step's choices deterministically (research
R9) and the step is absent from the strip. The step strip renders from the list of shipped steps,
not from a hardcoded five.

---

## Step 1 — Identity

**Asks**: name, species, class, background.

**Shows**, per FR-017:

| Selection | Detail shown | Source |
|---|---|---|
| Species | name, size, speed, and its traits | `Species.get/1`, `grants/1`'s `features` |
| Class | name, hit die, primary ability, saving throws, level 1 features | `Classes.get/1`, `grants/1` |
| Background | the three abilities it can raise, the skills it grants, the origin feat | `Backgrounds.get/1`, `grants/1` |

Every word of that comes from the content library. The component holds no rules prose (FR-006).

**Deferred choices are named, not asked** (FR-007): the class card says at which level its subclass
arrives, reading `class.subclass_level`. It does not offer one.

**Name field**: `phx-change` debounced at 400 ms, which sets `name_status` to `:checking` and then
to `:available`, `:taken`, or `:invalid`. The check is one indexed query against
`lower(character_name)`. It is a courtesy, not a reservation — the authoritative check happens at
confirmation (FR-012, and the spec's edge case says so directly).

---

## Step 2 — Abilities

**Asks**: the standard array assignment, then the background's increase spread.

The array is six values assigned across six abilities, each used once. Assigning a value already
held by another ability **swaps** them, which keeps the assignment complete at every moment rather
than letting it pass through an invalid state (spec US2 scenario 2).

The spread offers the shapes `Background.spreads/0` returns — `[2, 1]` and `[1, 1, 1]` — over only
the abilities in `grants/1`'s `abilities`. Choosing `[1, 1, 1]` assigns itself and asks nothing
further.

Every ability shows its **final** score and modifier including the increase (FR-021), computed by
`Srd.Rules.Ability.modifier/1`.

Changing the background clears the spread, because the new one names different abilities.

---

## Step 3 — Skills

**Asks**: the class' skill picks.

Shows the granted skills from `grants/1`'s `skills` as already held and not selectable, and offers
`class.skill_choice.from` minus those, with `class.skill_choice.choose` picks available. A pick can
never be spent on a skill the character already holds (FR-024), so the overlap case where fewer
distinct skills remain than the class allows picks still reaches a complete character.

Each option shows the ability it keys off and the modifier the character would have, which is the
detail that makes one pick better than another (spec US3's "why this priority").

---

## Step 4 — Specializations

**Asks**: everything `Srd.Character.choices/1` returns that the earlier steps did not.

This step has no per-choice code. It maps over the open choices and renders each one with a single
component driven by `choice.kind`:

| `kind` | Rendered as | Option labels from |
|---|---|---|
| `:lineage` | option cards with feature text | `Lineage.name` + its features |
| `:size` | a small radio row | the size atoms |
| `:feat` | option cards | `Feats.get/1` name and text |
| `:weapon` | a multi-select list | `Weapons.get/1` name |
| `:tool` | a select | `Items.get/1` name |
| `:feature` | option cards | the option strings themselves |
| `:skill` | as step 3 renders skills | `Skill.name/1` |

A species or class that offers nothing here shows nothing, and the step is skipped entirely when
`choices/1` returns an empty list for the selections (FR-026). A new kind of choice added to the
content library renders through the row that matches its kind with no change to this component,
which is FR-009 on the presentation side.

**Already-granted options are shown as held and are not selectable**, exactly as the skills step
treats a background-granted skill. A `:feat` choice filters out anything in `grants/1`'s `feats`
and labels it "already granted by your background", so a human whose background grants Alert cannot
spend Versatile on Alert and be told nothing. That is the spec's duplicate-feat edge case, and
handling it here rather than by deduplicating at creation is what makes the pick visible rather
than silent. The same filter applies to `:skill`-kind choices reached through this step, such as a
human's Skillful.

---

## Step 5 — Review

Renders `Srd.Character.derive/1` on the draft's facts, through the **same components the character
sheet uses**. That is the whole mechanism behind FR-029's "the reviewed character and the created
character MUST be identical": there is one derivation and one set of components, and both paths go
through them.

Shows everything FR-028 lists — name, species, class, background, the six scores with modifiers,
hitpoints, armor class, initiative, proficiency bonus, saving throws, skills — plus the features
and feats from `grants/1` and the picks from the draft.

Confirm is available only when the validator returns `:ok`. When it does not, the review names the
step that is incomplete rather than saying "something is wrong".

---

## Events

All in `AgenticRealmsWeb.GameLive.Creation`, a helper module beside `PlayerCommands`,
`Communication`, `Wizard`, and `UIEvents`.

| Event | Params | Effect |
|---|---|---|
| `creation_name` | `%{"name" => n}` | sets `name`, debounced availability check |
| `creation_select` | `%{"field" => f, "value" => v}` | sets species / class / background, runs invalidation |
| `creation_assign_ability` | `%{"ability" => a, "value" => v}` | assigns or swaps an array value |
| `creation_spread` | `%{"shape" => s, "abilities" => [...]}` | sets the background spread |
| `creation_pick` | `%{"key" => k, "value" => v}` | toggles a pick within a choice, respecting `choose` |
| `creation_step` | `%{"step" => s}` | moves to a reachable step |
| `creation_confirm` | — | validate, dispatch, `enter_world/1` or render errors |

Every one of them updates the draft in socket assigns and re-renders. None touches world state
until `creation_confirm`.

### Why these are round trips

Principle III asks for the reason whenever an interaction could plausibly be local, and feature 020
deliberately kept the character sheet's tabs off the server, so the difference is worth stating.

A sheet tab shows a panel that is already in the DOM; the server has nothing to add, so it must not
be asked. A creation selection changes **which questions exist** — pick an elf and a lineage
question appears, pick a dwarf and it does not — and the answer to "which questions" comes from
compile-time content that lives on the server. Rendering it client-side would mean shipping the
content library to the browser. That is the "data the client must not hold" case the principle
allows for.

The availability check needs the database by definition. Confirmation persists.

Cost: one round trip per click, each one a compile-time content read and a struct update, with no
database access and no world state touched. Off any hot path, once per player, for about three
minutes.

### What stays local

Nothing needs a JS hook. Step *visibility* is server-rendered only because each step's content
depends on prior selections; there is no client-side state to keep. The existing sheet tabs are
untouched.

---

## Styling

New rules in `assets/css/game.css`, following the existing `gm-` dialog conventions: a step strip
reusing the `sheet-tabs` treatment, option cards for species/class/background/lineage/feat, an
ability assignment grid, and a review panel that reuses the character sheet's panel styles.

The species with ten lineages (dragonborn) is the layout stress case — the option grid scrolls
within the dialog body rather than growing it, so every option stays reachable on a small screen
(spec edge case).

---

## Testing

`test/agenticrealms_web/live/character_creation_dialog_test.exs`:

- A player with no character sees the dialog; a player with one does not.
- The dialog renders no close button, no click-catching backdrop, and no Escape binding, and cannot
  be dismissed by any of the three.
- Confirm is unavailable until a name and all three selections are present, and the dialog says
  what is missing.
- Two live sessions for one player both confirm: one character exists and the second session enters
  the world rather than being shown an error.
- A feat granted by the background is shown as held and cannot be picked again.
- Selecting an elf shows a lineage question; selecting a dwarf shows none.
- Selecting a human shows a size question; selecting an elf does not.
- Selecting a fighter shows Fighting Style and Weapon Mastery, and says the subclass arrives at 3.
- Changing the class clears the skill picks and keeps the name, species, and background.
- Changing the background clears the spread.
- Assigning an array value already held swaps the two abilities.
- A skill granted by the background is shown as held and cannot consume a pick.
- The review's numbers equal `Srd.Character.derive/1` on the same facts.
- Confirming creates the character and the player lands in the starting room.
- Confirming a taken name keeps the dialog open with every choice intact.
- Disconnecting mid-creation leaves no `player_state` row.

`test/agenticrealms_web/live/character_creation_test.exs` is rewritten: it currently asserts the
generated default character arrives with no prompt, which is the behaviour this feature removes.
