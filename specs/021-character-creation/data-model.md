# Phase 1 Data Model: Interactive Character Creation

**Feature**: 021-character-creation | **Date**: 2026-08-01 | **Plan**: [plan.md](./plan.md)

Two things hold state in this feature: a draft that lives only as long as the dialog, and a
character that lives as long as the player. This file says what each holds, what writes it, and what
it is checked against.

---

## 1. The draft

`AgenticRealms.World.CharacterDraft` — a struct in the LiveView's socket assigns. Never persisted,
never broadcast, never in a registry. It dies with the socket, which is what FR-003 and FR-032's
"abandoning leaves no trace" require.

```elixir
%CharacterDraft{
  step: :identity,                 # :identity | :abilities | :skills | :specializations | :review
  name: "",                        # trimmed on validation, not on keystroke
  name_status: :unchecked,         # :unchecked | :checking | :available | :taken | :invalid
  species_slug: nil,
  class_slug: nil,
  background_slug: nil,
  array: %{},                      # %{Ability.t() => integer()} — the standard array assignment
  spread: nil,                     # {:split, %{str: 2, con: 1}} | {:even, [:str, :con, :cha]}
  skill_picks: [],                 # [Skill.skill()] — the class' picks only
  choices: %{},                    # %{choice_key() => [term()]} — everything else, by key
  errors: []                       # [{field, message}] — from the validator, for display
}
```

**`choices` is keyed by whatever `Srd.Character.choices/1` returns**, so the draft never names a
kind of decision. A fighter's draft holds `%{{:feature, "Fighting Style"} => ["defense"],
{:feature, "Weapon Mastery"} => ["longsword", "greatsword", "handaxe"]}` without the struct, the
LiveView, or the validator knowing that fighting styles exist. This is what makes FR-009 hold.

### Invalidation

FR-018 requires a changed selection to clear exactly the dependent choices and leave the rest.
The rule is one function, and it is expressed as "keep what is still offered":

| Changed | Cleared | Kept |
|---|---|---|
| `name` | nothing | everything |
| `species_slug` | every `choices` entry sourced from the old species | name, class, background, array, spread, skill picks |
| `class_slug` | `skill_picks`; every `choices` entry sourced from the old class | name, species, background, array, spread, species choices |
| `background_slug` | `spread` | everything else |

Implemented by re-running `Srd.Character.choices/1` for the new selections and dropping every draft
entry whose key is not in the new result, rather than by a table of what depends on what. The table
above is the observable consequence, not the implementation. `spread` is cleared on a background
change because the new background names different abilities (FR-020, spec US2 scenario 7).

### Step gating

A step is reachable when every earlier step is complete. `:review` is reachable only when the
validator returns `:ok`, which is what makes confirm unavailable with an incomplete choice
somewhere earlier.

---

## 2. The character

### Persisted columns on `player_state`

Feature 020 added the character columns. This feature adds three and changes nothing existing.

| Column | Type | Null | Source | Notes |
|---|---|---|---|---|
| `character_name` | `:string` | yes | `CharacterCreated` | Nullable at the database, guaranteed by the write side. See below. |
| `lineage_slug` | `:string` | yes | `CharacterCreated` | `nil` for the four species that offer no lineage. |
| `choices` | `:map` | no, default `%{}` | `CharacterCreated` | Picks with no typed column: tools, weapon masteries, feature options. |

Plus one index:

```elixir
create index(:player_state, ["lower(character_name)"], name: :player_state_character_name_lower_idx)
```

**Why `character_name` is nullable.** Either projector clause may create the row: `ensure_character`
ordering means `CharacterCreated` normally inserts it, but the existing comment on the projector is
explicit that "neither clause may assume the other has run — a replay from position 0 can deliver
them in either order". A `NOT NULL` would make a `PlayerSpawned`-first replay crash the projector.
The write side guarantees the value; the column tolerates the ordering.

**Why the index is not unique.** Research R3. Names are checked rather than reserved (§3), so a
duplicate is a permitted outcome; a unique constraint would turn one into a halted projection for
every player rather than the harmless collision FR-013 allows.

**What `choices` holds.** A map keyed by the string form of the choice key, valued by a list of the
picked slugs or option names:

```elixir
%{
  "class_tool" => ["thieves-tools"],
  "feature:Fighting Style" => ["defense"],
  "feature:Weapon Mastery" => ["longsword", "greatsword", "handaxe"]
}
```

Skill picks, feat picks, and the ability scores do **not** live here. They flatten into the typed
columns feature 020 already has, because those are the facts `Srd.Character.derive/1` consumes
(research R7). `choices` is for picks with no rules consumer yet, and it takes a new kind of choice
without a migration.

### Derived, never stored

Unchanged from feature 020: modifiers, proficiency bonus, saves, skills, passive perception, armor
class, initiative, hit dice, maximum hitpoints, and experience progress are all computed on read by
`Srd.Character.derive/1`. This feature adds nothing to the derived layer; it only changes where the
facts fed into it come from.

The **review** (FR-028, FR-029) calls the same `derive/1` on the draft's facts. That is the whole
mechanism behind "the reviewed character and the created character MUST be identical" — there is
one function and both paths call it.

---

## 3. Names

There is no reservation, no claim, and no aggregate. `Commands.create_character/2` asks
`PlayerNames.taken?/1` whether the name is already in use and refuses if it is.

The check reads `player_state.character_name` through the `lower(character_name)` index, so it is
case-insensitive and cheap. It runs twice: debounced in the dialog as the player types, which is a
courtesy, and again at confirmation, which is the one that decides.

**The window is deliberate.** Between the check and the projection, two players confirming the same
free name can both succeed. FR-013 permits it. Closing it would take either a uniqueness aggregate —
two dispatches, a compensating command, and a claim that outlives a dying node — or a reservation
table written outside a projector. Both cost more than a rare cosmetic collision, and research R2
records the full comparison along with which one to reach for if the guarantee is ever wanted.

---

## 4. Commands and events

### Extended: `CreateCharacter` / `CharacterCreated`

Three fields added to each. Everything else is unchanged from feature 020.

```elixir
%CreateCharacter{
  player_id:, character_name:,                       # + character_name
  species_slug:, class_slug:, background_slug:, size:,
  lineage_slug:,                                     # + nil when the species offers none
  abilities:, skill_proficiencies:, save_proficiencies:, feat_slugs:,
  choices:,                                          # + the keyed map
  max_hp:
}
```

`CharacterCreated` mirrors it and adds `hp` equal to `max_hp`, as it does today.

The command still carries a finished character and the aggregate still generates nothing, looks
nothing up, and defaults nothing. Validation happens in the facade before dispatch (research R8), so
the aggregate reads no compile-time content at `execute/2` time. Its guard is unchanged: it emits
only when `species_slug` is unset.

### No new commands or events

Creation adds none. `CreateCharacter` stays routed to `Player`, and the router is unchanged.

---

## 5. The projector

One clause changes. `PlayerStateProjector`'s `CharacterCreated` handler gains the three new fields
in its **identity** list — the values it sets on insert and on conflict alike, because the event is
the record of them:

```elixir
identity = [
  character_name: e.character_name,
  species_slug: e.species_slug,
  # ... unchanged ...
  lineage_slug: e.lineage_slug,
  choices: e.choices
]
```

The `seeded` list (`level`, `xp`, `hp`) is untouched, so a redelivered or replayed
`CharacterCreated` still cannot knock a level 7 player back to 1. Every new value is absolute and
comes from the event, so re-handling remains a no-op.

No new projector, and `CharacterNameClaimed` gets none.

---

## 6. The creation path

`AgenticRealms.World.Commands.create_character/2` replaces `ensure_character/1`.

```
create_character(player_id, %CharacterDraft{} = draft)
  1. CharacterGen.complete(draft)                  → a draft with every choice filled
  2. CharacterDraft.Validator.validate(complete)   → :ok | {:error, [{field, message}]}
  3. PlayerNames.taken?(name)                      → {:error, :name_taken} if so
  4. dispatch CreateCharacter, consistency: :strong
  5. {:ok, :created}
```

**Step 1 is what makes the spec's story ordering work.** A draft only carries the choices a shipped
story asked for; while stories 2 through 4 are unshipped, the dialog never asks for ability scores,
skill picks, or lineage, so the draft reaches the facade incomplete. `CharacterGen.complete/1` fills
exactly what the player was not asked, from the same options `Srd.Character.choices/1` offers, and
returns a whole character. Once all five stories ship, the dialog leaves no gaps and every fill
stops firing on its own — the code stays, because `CharacterGen.default/0` still needs it for seeds
and tests (research R9). No story ever deletes a fill.

**Validation runs on the completed draft, not the submitted one**, which is why every row of §7 is
unconditional. It also means a `CharacterGen` bug is caught by the validator rather than reaching
the aggregate. Generated fills are drawn from the same offered options, so they cannot fail
validation, and every error the player sees is therefore about something they entered.

The dispatch is `:strong` so that by the time the LiveView continues into `enter_world/1`, the
`player_state` row exists with a complete character. That is the same guarantee feature 020's mount
ordering relied on, and `Stats.for_player/1` still raises if it is ever violated.

One dispatch, so there is nothing to compensate: a failure leaves no trace anywhere and the player
retries with every choice intact.

### `CharacterGen.complete/1`

```elixir
@spec complete(CharacterDraft.t()) :: CharacterDraft.t()
```

Takes a draft and returns one with every open decision settled. It fills only what is missing, so a
choice the player made is never overwritten:

| Missing | Filled with |
|---|---|
| `array` | the standard array dealt down `ability_priority/1`, as today |
| `spread` | `[2, 1]` on the highest-priority abilities the background offers, as today |
| `skill_picks` | the best-modifier picks from `class.skill_choice`, excluding granted, as today |
| any key in `Srd.Character.choices/1` with no entry | the first option, deterministically |

Species, class, and background are **not** filled. They are story 1's, so they are always the
player's, and a draft reaching the facade without them is a validation error rather than something
to guess at.

Still pure and still deterministic: no repository access, no randomness, two identical drafts
produce two identical characters.

### Mount ordering

```
mount
 ├─ PlayerNames.get(player_id)
 │    nil  → assign(phase: :creating, draft: CharacterDraft.new()) and stop
 │    name → enter_world(socket)
 └─ (on confirm) create_character/2 → enter_world(socket) → assign(phase: :playing)
```

`enter_world/1` is everything mount does today from `Commands.spawn/2` onward: spawn, `look_room`,
inventory, presence, the PubSub subscriptions, `fire_for_arrival`, and the assigns. It is extracted
rather than duplicated so the two entry points cannot drift.

---

## 7. Validation rules

`CharacterDraft.Validator.validate/1` returns `:ok` or `{:error, [{field, message}]}`. It knows no
SRD rules; it compares the draft against what the package offered (research R8).

**It runs on a completed draft** (§6 step 1), so every rule below is unconditional. The validator has
no notion of which story has shipped and no "skip this if empty" clause — an empty `skill_picks` is
an error, and it is `CharacterGen.complete/1`'s job to make sure the facade never presents one.

| Field | Rule | Source of truth |
|---|---|---|
| `name` | non-empty after trim, ≤ 32 characters | FR-011 |
| `species_slug`, `class_slug`, `background_slug` | present, and resolve to real content | `Species.get/1`, `Classes.get/1`, `Backgrounds.get/1` |
| `array` | a permutation of the standard array across the six abilities, each ability once | `Srd.Rules.Ability.standard_array/0`, `Ability.all/0` |
| `spread` | shape matches one of the allowed spreads; every ability named is one the background offers | `Srd.Content.Background.spreads/0`, `background.ability_scores` |
| final scores | none exceeds 20 | FR-022 |
| `skill_picks` | count equals `class.skill_choice.choose`; every pick is in `class.skill_choice.from`; no pick duplicates a granted skill | `Srd.Character.grants/1`, the class' `Choice` |
| `choices` | for each choice `Srd.Character.choices/1` returns: exactly `choose` picks, each one in `from`; no extra keys | `Srd.Character.choices/1` |

The last row is the one that matters. It is set membership over whatever came back, so a choice the
package gains tomorrow validates correctly with no change here.

The name check is deliberately **not** in this table. Whether a name is taken is a property of the
world rather than of the draft, so the facade asks it at step 3 rather than the validator asking it
here.

---

## 8. Player identity

`AgenticRealms.World.PlayerNames` becomes the one place the world asks what a player is called.

```elixir
@spec get(integer()) :: String.t() | nil        # nil means "no character yet"
@spec get_many([integer()]) :: %{integer() => String.t()}
@spec find_by_name(String.t()) :: integer() | nil   # case-insensitive, uses the lower() index
```

It reads `player_state.character_name`. Nothing in `World` or `AgenticRealmsWeb` reads
`accounts.players.username` afterwards except the authentication path.

The world-facing map keys are renamed to match what they hold: `%{id:, username:}` becomes
`%{id:, name:}` in what `World.Queries` returns, and `actor_username` becomes `actor_name` in the
`World.UIEvents` structs. Every seam is enumerated in
[contracts/player-identity.md](./contracts/player-identity.md).

The external NPC API needs no contract change: `npc_service_controller.ex` already renames the
field to `name` in its JSON, so the published shape is unchanged and only its source moves.
