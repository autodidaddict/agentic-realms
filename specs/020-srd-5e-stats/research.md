# Phase 0 Research: SRD 5e Character Stats

**Feature**: 020-srd-5e-stats | **Date**: 2026-07-28 | **Spec**: [spec.md](./spec.md)

Seven questions had to be settled before the design would hold together. Each is recorded below with what was chosen, why, and what was rejected.

---

## R1. How the game consumes `srd_5e`

**Decision**: Add `{:srd_5e, path: "packages/srd_5e"}` to the root `mix.exs` as a runtime dependency.

**Rationale**: The package already lives in this repository at `packages/srd_5e` and is fully tracked in git (93 files). A path dependency compiles it as part of the umbrella build with no publishing step, no version pinning drift, and no separate release process. Its own dependency list is `ex_doc` for `:dev` only, so it adds nothing to the runtime.

Content is loaded at compile time inside the package (`Srd.Content.Species.Data` evaluates `priv/data/species.exs` with `@external_resource`), so lookups are compiled-in map reads. There is no process to supervise and nothing to add to the application tree.

**Alternatives considered**:

- *Publish to Hex and depend on `~> 0.2`.* Rejected. The package is volatile by its own README's admission, and this feature will add a module to it. A publish cycle per iteration is friction with no benefit while both live in one repo.
- *Copy the rules the game needs into `AgenticRealms.World`.* Rejected outright. FR-006 makes the library the single source of SRD truth, and duplication is exactly what the library exists to prevent.
- *Git dependency on the same repo.* Rejected. Self-referential, and it would resolve to a committed SHA rather than the working tree.

---

## R2. Where the experience table lives

**Decision**: A new `Srd.Rules.Experience` module in the package, holding the SRD 5.2 twenty-level table and the calculations over it. `AgenticRealms.World.LevelCurve` is deleted.

**Rationale**: Directed by the user during clarification, and correct on its own merits: the table is SRD content in exactly the same sense as `Srd.Rules.Proficiency`'s level schedule, which already lives there. Keeping the two in separate repositories would be the odd choice, since they change together and are read together.

The module sits alongside `Proficiency` under `Srd.Rules`, follows the package's existing test convention (`test/srd/rules/experience_test.exs`, `async: true`, `describe` per function), and gets a CHANGELOG entry under `[Unreleased]`.

**API shape**: deliberately mirrors the `LevelCurve` it replaces, so the aggregate and projector swap is mechanical:

| `World.LevelCurve` (deleted) | `Srd.Rules.Experience` (new) |
|---|---|
| `threshold(level)` | `threshold(level)` |
| `level_for_xp(xp)` | `level_for_xp(xp)` |
| `progress(xp)` | `progress(xp)` |
| — | `max_level()` → `20` |
| — | `table()` → the twenty thresholds |

The one behavioral difference is the cap. `LevelCurve` was unbounded, so `progress/1` always had a next threshold. At level 20 there is none, so `progress/1` returns `to_next: nil, fraction: 1.0` and callers treat that as "fully levelled". This is the only place the swap is not a rename.

**Alternatives considered**:

- *Keep `LevelCurve` in the game and have it read a table from the package.* Rejected. It leaves a game module whose only job is to forward, and the user asked for the calculations in the package, not just the data.
- *Keep the quadratic and cap it at 20.* Rejected during clarification.
- *Make the table an `edition:` opt-in like ADR-0003's divergences.* Rejected. SRD 5.1 and 5.2 share this table, so there is nothing to choose between.

---

## R3. Where character identity lives, and how it is created

**Decision**: Aggregate-owned, created by a new `CreateCharacter` command emitting a new `CharacterCreated` event. Not folded into `PlayerSpawned`.

**Rationale**: Two things force it, and a third made it free.

Creation and spawning are genuinely different life events. A character is made once; it enters the world every session. Feature 019 conflated them because the "creation" was six hardcoded 12s, which needed no ceremony.

Interactive creation is the next milestone, and the spec says so explicitly. It wants to dispatch this same command with player-chosen values rather than reshape the spawn path.

FR-027 was the third argument when this was first written: every existing player is already spawned, and `Commands.spawn/2` short-circuits when the read model shows a current room, so folding creation into `PlayerSpawned` would leave every pre-existing character permanently blank. That argument no longer carries weight, because the world is purged and restaged for this feature (see R8) and no character predates it. The design is unchanged, because the first two arguments stand on their own — but the per-mount `ensure_character/1` dispatch is now belt-and-braces rather than the mechanism FR-027 depends on.

**Mechanics**: `GameLive.mount` dispatches `Commands.ensure_character(player_id)` **before** the existing `Commands.spawn/2` call, at `consistency: :strong`. The aggregate guards on `species_slug == nil`: already created returns `:ok` with no event.

Creation-first is the ordering because it means the `player_state` row is born complete. `Queries.current_room_of/1` returns `{:error, :no_current_room}` for a row whose `current_room_id` is `NULL` just as it does for a missing row, so `spawn/2` still dispatches correctly against a row that already exists. Both projector clauses are upserts, so neither depends on the other having run.

The alternative — spawn first, `CharacterCreated` as a plain update — was rejected once purge-and-restage was on the table. It requires the row to exist in a half-formed state with placeholder ability scores for the width of one dispatch, and it requires the schema and the migration to carry defaults whose only job is to fill that gap.

**Alternatives considered**:

- *Extend `SpawnPlayer`/`PlayerSpawned` with the character payload.* Rejected on FR-027, above. Also makes the event mean two things.
- *A read-model-only character with no event.* Rejected under Principle II: read models are written only by projectors reacting to events, and the character is durable state a player earns and later edits.
- *Generate lazily on first sheet read.* Rejected. A read path that writes is the back door Principle II exists to close.

---

## R4. Where generation happens

**Decision**: In a pure `World.CharacterGen` module, called by the `Commands.ensure_character/1` facade. The command carries the fully-generated character; the aggregate only records it.

**Rationale**: An aggregate must produce the same events when its stream is replayed. If the aggregate read the configured default class at `execute/2` time, changing that config later would silently rewrite what every past player was created as. Generating outside and carrying the result in the command means `CharacterCreated` records what was actually created, permanently.

It also keeps generation unit-testable without Commanded or the database, which Principle IV asks for, and it is the seam interactive creation will use: the same command, filled from a form instead of from defaults.

**Alternatives considered**:

- *Generate inside `execute/2`.* Rejected on replay-determinism, above.
- *Generate in the projector.* Rejected. Projectors derive from events; they do not invent state.

---

## R5. Derived values: computed or stored, and computed where

**Decision**: Computed on read, and computed **in the package**. `Srd.Character.derive/1` takes a character's facts and returns every derived value. Nothing derived is persisted, and the game performs no SRD arithmetic of its own.

**Rationale**: Two separate questions, settled together.

*Computed, not stored*, because FR-006 requires it and the arithmetic is trivial — six floored divisions, a table lookup, and a couple of dozen additions. Storing the results would create a second source of truth that drifts the moment a score or level changes, and would need a migration every time a value was added to the sheet.

*In the package*, because that is where SRD rules belong, and a derived value is as much an SRD rule as the table it reads from. An earlier draft of this plan put the composition in an `AgenticRealms.World.Character` module and left only the leaf calculations in the library. The user corrected it during task planning, and the correction is right: splitting composition from primitives puts half the sheet's rules in each repository, and the half in the game is the half nobody else can reuse. `Srd.Rules.Save.modifier/3` in the library while the saving-throw *row* is assembled in the game is an arbitrary line.

The game keeps what is genuinely not an SRD rule: reading `player_state`, shaping for display, and the *choices* generation makes. The SRD says a character picks a skill; it does not say which. That is `World.CharacterGen`'s business, and it calls the package for the standard array and the background's legal spreads.

Six primitives are added to the package alongside the composition, because `derive/1` needed them and they were missing: `Ability.all/0`, `Ability.name/1`, `Ability.standard_array/0`, `Skill.name/1`, `Save.modifier/3`, and `Initiative.modifier/1`, plus `Hitpoints.maximum/3` and `hit_dice/2`.

**Alternatives considered**:

- *Persist derived columns and recompute in the projector on every stat event.* Rejected. More columns, more migration surface, and a projector that has to know the SRD rules.
- *Compose in `AgenticRealms.World.Character`, leaving only leaf calculations in the package.* This was the original decision, reversed. It read as consistent with ADR-0004's "holds no character of its own", but that sentence rules out a stored character record, not a pure function over stated facts. `derive/1` stores nothing.
- *A `Srd.Character` struct holding a whole character.* Still rejected, and this is the distinction that matters. `derive/1` takes a map and returns a map. The package gains no character type, no constructor, and no state — only the arithmetic.

ADR-0004 is worth a short amendment recording that the package owns the derived layer as well as the content, since its current wording could fairly be read to exclude it.

---

## R6. Removing mana

**Decision**: Drop `mana` and `max_mana` from the Player aggregate, `player_state`, and every UI surface. Leave the `npc_clones` and `blueprints` columns alone.

**Rationale**: FR-032 and FR-033 remove it from the player model; FR-034 forbids touching NPC records this milestone. Dropping the player columns and leaving the NPC ones is not inconsistent, it is the scope line the user drew: NPC mana becomes an unread column that the NPC stat-block feature will deal with when it reshapes those rows anyway.

The `hp_bar` component keeps its `kind="mp"` variant. Nothing calls it after this feature, but it costs nothing and the spells milestone will want a resource bar.

**Alternatives considered**:

- *Keep the columns and stop reading them.* Rejected for `player_state`. A NOT NULL column nobody reads is the kind of thing that survives three features and then confuses someone.
- *Drop the NPC columns too.* Rejected. That is an NPC record change, which FR-034 forbids.

---

## R7. Rescaling the quest reward

**Decision**: The orchard quest's reward goes from `"xp" => 100` to `"xp" => 300`.

**Rationale**: Feature 019 set it to 100 with the comment "100 xp lands a fresh player exactly at Level 2." Under the SRD table level 2 is at 300, so 300 preserves that intent exactly. It is the only seeded XP reward in the world, so this is the whole of FR-031.

**Alternatives considered**:

- *Leave it at 100 and rebalance later.* Rejected. It would take three quests to reach level 2 when only one quest exists, so a new player would never level at all.
- *Rescale by the ratio of the two curves at every level.* Rejected as premature. One reward, one number.

---

---

## R8. Purge and restage rather than preserve

**Decision**: `mix world.reset` is the upgrade path. No back-compatibility is kept for player stats, and no backfill code is written.

**Rationale**: The project is pre-launch with no real users, the event log is destroyable by standing policy, and the user confirmed this explicitly during task planning. The repository already carries the alias for exactly this: `world.reset` runs `event_store.reset` then `ecto.reset`, dropping and recreating both databases, re-running migrations, and reseeding.

What this buys, concretely:

- The migration carries no defaults whose only purpose is keeping pre-existing rows valid. The only defaults left are the empty proficiency arrays, which serve a runtime window, not a historical one.
- The `PlayerState` schema drops feature 019's `str: 12` style field defaults entirely. Every character is created by `CharacterCreated`, so a placeholder score is never correct and never read.
- No backfill task, no migration-time data script, and no "characters created before this feature" test path. FR-027 is satisfied by the world being new.

Note that `ecto.reset` drops the read-model database, which holds the `players` accounts table. Accounts go with it and are re-registered. That is the intended cost of a clean slate.

**Alternatives considered**:

- *A data migration filling character columns for existing rows.* Rejected. It would have to reimplement generation in SQL or in a migration module, and the generated values would be stale the moment the defaults changed.
- *Rewriting feature 019's migration in place so mana is never added.* Rejected. The migration ledger is append-only by convention here, and thirty-odd migrations deep is the wrong place to start editing history. Adding a column in one migration and dropping it in the next is ordinary.

---

## Resolved unknowns

Every `NEEDS CLARIFICATION` from the spec was settled in `/speckit.specify` before planning began: the experience table (R2), the mana pool (R6), and NPC scope (unchanged, no research needed). No unknowns remain in Technical Context.
