# Contract: Commands, Events, and Aggregates

**Feature**: 021-character-creation

One command/event pair extended, one facade function replacing another, and a change to mount
ordering. No new aggregate — see below.

---

## No new aggregate

An earlier draft of this feature added a `CharacterName` aggregate, keyed by the normalized name, so
that Commanded's per-stream serialization would make names strictly unique. It was built and then
removed. Research R2 records why in full; the short version is that a character is keyed by its
player rather than by its name, so the trick that makes blueprint slugs unique for free costs a
second aggregate here — and with it two dispatches, a compensating command, and a claim that
outlives a node dying between them. That is a two-phase commit with a known hole, in exchange for
preventing a collision that needs two players to confirm the same name in the same millisecond.

FR-013 was relaxed instead. Names are checked at confirmation and not reserved, so this feature adds
no aggregate, no command, and no event beyond extending the two that already existed.

## Commands and events

### `CreateCharacter` → `CharacterCreated` (extended)

Three fields added to each; nothing existing changes.

```elixir
%CreateCharacter{
  player_id:,
  character_name:,        # NEW
  species_slug:,
  class_slug:,
  background_slug:,
  size:,
  lineage_slug:,          # NEW — nil for a species that offers none
  abilities:,
  skill_proficiencies:,
  save_proficiencies:,
  feat_slugs:,
  choices:,               # NEW — %{String.t() => [String.t()]}, keyed by choice key
  max_hp:
}
```

`CharacterCreated` mirrors it and still adds `hp` equal to `max_hp`.

The rule feature 020 set holds: the command carries a finished character, and the aggregate
generates nothing, looks nothing up, and defaults nothing. Validation runs in the facade before
dispatch, so the aggregate reads no compile-time content at `execute/2` time and a replay cannot
disagree with what was recorded.

The `Player` aggregate's guard is unchanged — it emits only when `species_slug` is unset — so a
second `CreateCharacter` for the same player is still a no-op, which is half of FR-004. The other
half is that the facade only ever dispatches it once per confirmation.

`version: 1` stays. The event log is destroyable in the current phase, so extending the shape needs
no stream migration and no version bump; the world is reseeded and the new shape starts appearing.

---

## The facade

`AgenticRealms.World.Commands.create_character/2` replaces `ensure_character/1`, which is deleted.

```elixir
@spec create_character(integer(), CharacterDraft.t()) ::
        {:ok, :created}
        | {:error, :name_taken}
        | {:error, [{atom(), String.t()}]}
        | {:error, term()}

def create_character(player_id, %CharacterDraft{} = draft) do
  complete = CharacterGen.complete(draft)

  with :ok <- CharacterDraft.Validator.validate(complete),
       :ok <- name_available(complete.name),
       :ok <- create(player_id, complete) do
    {:ok, :created}
  end
end
```

**Ordering**: complete, validate, check the name, create.

Completing first is what lets a story ship alone. A draft only carries the choices a shipped story
asked for, so while stories 2 through 4 are unshipped it arrives with no ability scores, no skill
picks, and no lineage. `CharacterGen.complete/1` fills exactly what the player was not asked, from
the same options `Srd.Character.choices/1` offers, and hands the validator a whole character. That
is why the validator has no "skip if empty" clause and why every rule in data-model.md §7 is
unconditional. Once all five stories ship, `complete/1` fills nothing.

Checking the name before dispatching means a taken name fails before anything is written to the
player's stream, so a refusal leaves no trace on the character. The check is not a reservation — see
the note above and research R2.

**Consistency**: the dispatch is `:strong`. By the time `create_character/2` returns `:ok`, the
`player_state` row exists with a complete character, which is what `enter_world/1` steps into
immediately afterwards. This is the same guarantee feature 020's mount ordering relied on, and
`Stats.for_player/1` still raises loudly if it is ever violated.

**Nothing to compensate**: one dispatch, so a failure leaves no trace anywhere and the player
retries with every choice intact.

**Errors reach the dialog intact.** `{:error, :name_taken}` and `{:error, [{field, message}]}` both
render in place with every choice preserved, which is FR-032.

---

## Mount ordering

```
GameLive.mount/3
 │
 ├─ PlayerNames.get(player_id)
 │
 ├─ nil ──→ assign(phase: :creating, draft: CharacterDraft.new())
 │          render the shell with an inert pane and the creation modal
 │
 └─ name ─→ enter_world(socket) ─→ phase: :playing
```

and on confirmation:

```
handle_event("confirm_character", ...)
 └─ Commands.create_character(player_id, draft)
      {:ok, :created} ──→ enter_world(socket) ─→ phase: :playing, modal closed
      {:error, _}     ──→ assign the errors, keep the draft, stay in :creating
```

`enter_world/1` is extracted from mount and holds everything mount does today from
`Commands.spawn/2` onward: spawn, `look_room`, inventory, presence, the three PubSub subscriptions,
the wizard blueprint subscription, `Behaviors.Interpreter.fire_for_arrival/2`, and the assigns. It
is extracted rather than duplicated because the confirm handler needs every line of it and two
copies would drift.

`ensure_character/1` and its `has_character?/1` read-model short-circuit are deleted. There is now
exactly one way a character comes into being, which is the point of FR-004.

---

## Testing

**Player aggregate** (`player_create_character_test.exs`, extended):

- `CreateCharacter` with the three new fields emits them on `CharacterCreated`.
- A second `CreateCharacter` still emits nothing.
- `lineage_slug: nil` round-trips for a species with no lineage.

**Projector** (`player_state_projector_character_test.exs`, extended):

- The three new columns are set on insert and on conflict.
- A redelivered `CharacterCreated` still does not reset `level`, `xp`, or `current_room_id`.
- A `PlayerSpawned`-first replay does not crash on a null `character_name`.

**Facade** (`create_character_facade_test.exs`):

- The happy path creates exactly one character.
- A name another character holds returns `{:error, :name_taken}` and writes nothing to the player's
  stream, matching regardless of case.
- An invalid draft returns the field errors and dispatches nothing at all.
- **A draft carrying only a name, species, class, and background** — the US1 shape — completes and
  creates a legal character. This is the test that would have caught the pipeline missing its
  completion step.
- A draft whose choices the player did make is not overwritten by completion.
- A second `create_character/2` for a player who already has one creates no second character.
