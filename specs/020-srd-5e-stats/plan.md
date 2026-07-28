# Implementation Plan: SRD 5e Character Stats

**Branch**: `020-srd-5e-stats` | **Date**: 2026-07-28 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/020-srd-5e-stats/spec.md`

## Summary

Replace feature 019's placeholder stat model with a real SRD 5.2 character, and rebuild the character sheet around it.

The game takes a path dependency on `packages/srd_5e` and delegates every SRD rule to it. Every SRD calculation moves into the package: `Srd.Rules.Experience` holding the twenty-level table, `Srd.Character.derive/1` composing a whole character sheet from stated facts, and eight supporting primitives the composition needed. `AgenticRealms.World.LevelCurve` is deleted, and the game keeps no SRD arithmetic of its own.

Three slices:

1. **A tabbed, SRD-shaped sheet** (P1). Three tabs — main stats, abilities and modifiers, spells — inside the existing modal, with tab switching done client-side. The spells tab is a placeholder. The mana bar is removed from the sheet and the sidebar.
2. **Complete characters at creation** (P2). A new `CreateCharacter` command and `CharacterCreated` event give the Player aggregate a species, class, background, standard-array scores, and proficiency sets. Generation is a pure function of configured defaults, so it is deterministic and replay-safe.
3. **Derived values that follow the level** (P3). Proficiency bonus, maximum hitpoints, hit dice, saves, and skills are computed on read from level and the scores, so a level-up moves all of them with no extra events.

**Key design decisions (Phase 0, full rationale in [research.md](./research.md)):**

1. **`srd_5e` is consumed as a path dependency**, not published to Hex. It is in-repo and fully tracked, this feature adds modules to it, and its own dependencies are `:dev`-only. Content is compile-time loaded inside the package, so there is nothing to supervise.
2. **The experience table lives in `Srd.Rules.Experience`**, per the user's direction during clarification and because it is the counterpart to `Srd.Rules.Proficiency`'s level schedule, which is already there. Its API mirrors the deleted `LevelCurve` so the swap is mechanical, differing only in the level 20 cap.
3. **Character identity is created by a separate `CreateCharacter` command, not folded into `PlayerSpawned`.** Creation and spawning are different life events — a character is made once and enters the world every session — and this is the seam interactive creation will dispatch through next milestone. Dispatched idempotently at mount, before `SpawnPlayer`, using the same guard pattern `RecordRoomDiscovery` already uses.
4. **The world is purged and restaged rather than migrated.** `mix world.reset` already drops and recreates both databases; no character predates this feature, so the migration carries no compatibility defaults, the schema drops feature 019's placeholder stat defaults, and no backfill code is written.
5. **Generation happens outside the aggregate**, in a pure `World.CharacterGen`, and the command carries the finished character. An aggregate that read configuration at `execute/2` time would rewrite history when the default class changed.
6. **Nothing derived is persisted, and nothing derived is calculated in the game.** `Srd.Character.derive/1` in the package takes a character's facts and returns modifiers, proficiency bonus, saves, skills, passive perception, AC, initiative, hit dice, maximum hitpoints, and experience progress. `World.Stats.for_player/1` shrinks to an adapter: read the row, build the facts map, call `derive/1`. The game performs no SRD arithmetic.
7. **Tab switching is client-side.** Which tab is visible is not authoritative, persisted, or broadcast, so under Principle III it must not cost a round-trip.
8. **No new runtime dependency beyond `srd_5e` itself**, no new event handler, no new process, no new Horde registry.

## Technical Context

**Language/Version**: Elixir ~1.20 (OTP), Phoenix 1.8 / LiveView 1.1
**Primary Dependencies**: Commanded 1.4.x + commanded_eventstore_adapter + eventstore (PostgreSQL), Ecto/Postgrex 3.13, Phoenix.PubSub. **One new dependency**: `{:srd_5e, path: "packages/srd_5e"}` — our own in-repo package, pure Elixir, no runtime dependencies of its own.
**Storage**: Two PostgreSQL databases — event store (`AgenticRealms.EventStore`) and read model (`AgenticRealms.Repo`). **One read-model migration** adding seven character columns to `player_state` and dropping its two mana columns. No event-store migration; the event log is destroyable pre-launch, so `CharacterCreated` simply starts appearing.
**Testing**: ExUnit in both projects. The package carries the arithmetic and therefore most of the tests — `Srd.Rules.Experience`, `Srd.Character.derive/1` across every proficiency band, and each new primitive, all pure and `async: true`. In the app, `World.CharacterGen` is a DB-free unit test; aggregate `execute`/`apply`, the projector clause, and the sheet render use the established `AgenticRealms.DataCase` (Ecto SQL Sandbox + `@moduletag :commanded`) harness.
**Target Platform**: Linux server; multi-node BEAM cluster (Horde present). Cluster semantics are unchanged — `CreateCharacter` is a per-player-stream command dispatched from the player's own LiveView, and a race between nodes resolves to a single event because the aggregate is the sole writer of its stream.
**Project Type**: Web application (Phoenix LiveView front end + event-sourced domain backend) plus an in-repo pure Elixir library.
**Performance Goals**: The sheet is one indexed `Repo.get` by primary key plus roughly forty integer operations. Mount adds one strongly-consistent dispatch that emits no event after the first. Live updates patch from the broadcast payload for XP and re-read once per level-up, which is rare. Nothing per-tick or in a hot loop.
**Constraints**: Character stats change only through the Player aggregate; read models are written only by projectors; XP award stays idempotent under redelivery; examine must not leak exact numbers; the sheet must contain zero mock values and no mana anywhere; SRD rules must not be reimplemented in the game.
**Scale/Scope**: In the package, two new modules (`Srd.Rules.Experience`, `Srd.Character`) and eight primitives added across five existing rules modules. In the game, one new command and event, one new pure module (`CharacterGen`), one aggregate extended, one projector clause, one migration, and the character sheet plus sidebar rebuilt. One module deleted (`LevelCurve`). NPC records, blueprints, and the external NPC API are untouched.

**Unknowns**: none. The spec's three `NEEDS CLARIFICATION` markers were resolved during `/speckit.specify`; research.md records the eight design questions settled in Phase 0.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution v1.0.0 (ratified 2026-06-09). Assessment against the six principles:

| Principle | Assessment |
|---|---|
| **I. Cluster-Correct by Default (NON-NEGOTIABLE)** | **PASS.** No new stateful process, registry, or singleton. `CreateCharacter` is a per-player-stream command dispatched from the player's own LiveView, exactly as `SpawnPlayer` is, and `identify` already keys `Player` by `player_id`. Two nodes mounting the same player concurrently is safe by aggregate serialization: whichever dispatch lands second finds `species_slug` set and emits nothing. `XpAwarder` is unchanged and remains the only cross-aggregate reaction, still an exclusive named Commanded subscriber. Sheet assigns and tab visibility are node-local, which is correct — they are per-socket UI state. |
| **II. Event-Sourcing Invariants (NON-NEGOTIABLE)** | **PASS.** Character identity changes only via the Player aggregate: `CreateCharacter` → `CharacterCreated`, state through `apply/2`. `player_state` is written only by `PlayerStateProjector`; the new clause sets absolute values from the event, so re-handling is a no-op, and the existing `PlayerSpawned` `on_conflict` still refuses to reset earned progression. Nothing reads raw event data. Derived values are computed from the projected read model, never from the stream. The read path stays a read — generation happens in the command facade, not lazily on first sheet load, which was explicitly rejected in research R3. Event-shape changes need no stream migration under the pre-launch event-log policy; the world is reseeded. |
| **III. Local-First LiveView Interaction** | **PASS, and improved.** Tab switching is `Phoenix.LiveView.JS` show/hide with no `phx-click` reaching the server, because which tab is visible is not authoritative, persisted, or broadcast. The one server round-trip added anywhere is `ensure_character/1` at mount, which is justified under the principle: it persists durable state and must be authoritative. The live stats update re-reads the database only on a level change, where derived values genuinely move; XP-only updates patch from the broadcast payload without touching the database. |
| **IV. Test-First, Green-Before-Merge** | **PASS.** Pure units first and DB-free: `Srd.Rules.Experience` (all twenty thresholds, boundaries, the cap), the `Srd.Rules.Hitpoints` additions, `Srd.Character.derive/1` (every derived value at every proficiency band, against published SRD values), each new primitive, and `World.CharacterGen` (determinism, the documented default character, a non-default class). Then aggregate `execute`/`apply` for `CreateCharacter` including the idempotent second dispatch, the projector clause, the mount ordering, and the sheet render. `mix precommit` gates the app; `mix test` in the package gates the library. |
| **V. Clean Git History — No AI Attribution (NON-NEGOTIABLE)** | **PASS.** No attribution in any commit or PR on this branch. |
| **VI. Idiomatic Phoenix & Deliberate Simplicity** | **PASS.** One new dependency, and it is our own in-repo package existing precisely to hold these rules — FR-006 makes duplicating them the alternative. New game code is three small pure modules plus one command/event pair, all inside the existing `World` context, following the established aggregate/command/event/projector layering. The package additions follow its own struct-plus-rules convention and its test layout. Deliberate omissions: no `Srd.Character` struct in the library (ADR-0004 keeps the character out of it), no rolled-hitpoints variant with no caller, no tab-state assign where JS suffices. Deriving maximum hitpoints rather than accumulating it removes an event and a class of drift. |

**Design elements worth flagging**: none. Complexity Tracking is empty.

**Post-Design re-check**: PASS. Phase 1 introduced no machinery beyond the command/event pair and pure modules assessed above. The one design choice that could have bent a principle — generating the character lazily on first sheet read — was identified and rejected in research R3 precisely because it would put a write on a read path.

## Project Structure

### Documentation (this feature)

```text
specs/020-srd-5e-stats/
├── plan.md              # This file
├── research.md          # Phase 0 — eight decisions: dependency form, table placement,
│                        #   creation event, generation locus, derive-vs-store, mana,
│                        #   reward rescale, purge-and-restage
├── data-model.md        # Phase 1 — persisted vs derived, migration, command/event/aggregate,
│                        #   derivation rules, generation steps, the default character
├── quickstart.md        # Phase 1 — run it, see all three stories, verify the cap and examine
├── contracts/
│   ├── experience.md        # Srd.Rules.Experience — the SRD table and its functions
│   ├── hitpoints.md         # Srd.Rules.Hitpoints — starting/2, per_level/2, maximum/3, hit_dice/2
│   ├── character-derivation.md  # Srd.Character.derive/1 + the eight new primitives
│   ├── domain-events.md     # CreateCharacter / CharacterCreated, aggregate changes, mount ordering
│   └── character-sheet.md   # Three tabs, what each shows, client-side switching, live updates
├── checklists/
│   └── requirements.md  # Spec quality checklist (all pass)
└── tasks.md             # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

Two package modules, three new pure game modules, one command/event pair, one migration, and the sheet rebuilt. One module deleted.

```text
packages/srd_5e/
├── lib/srd/character.ex                 # NEW  derive/1 — the whole sheet from stated facts
├── lib/srd/rules/experience.ex          # NEW  SRD table: table/0, max_level/0, threshold/1,
│                                        #      level_for_xp/1, progress/1 (capped at 20)
├── lib/srd/rules/hitpoints.ex           # EDIT +starting/2, +per_level/2, +maximum/3, +hit_dice/2
├── lib/srd/rules/ability.ex             # EDIT +all/0, +name/1, +standard_array/0
├── lib/srd/rules/skill.ex               # EDIT +name/1
├── lib/srd/rules/save.ex                # EDIT +modifier/3
├── lib/srd/rules/initiative.ex          # EDIT +modifier/1
├── test/srd/character_test.exs          # NEW  every band 1/5/9/13/17/20 vs published SRD
├── test/srd/rules/experience_test.exs   # NEW  all 20 thresholds, boundaries, the cap
├── test/srd/rules/{hitpoints,ability,skill,save,initiative}_test.exs  # EDIT new primitives
└── CHANGELOG.md                         # EDIT [Unreleased] entry

mix.exs                                  # EDIT +{:srd_5e, path: "packages/srd_5e"}
config/config.exs                        # EDIT +:character_defaults (FR-010's single place)

lib/agenticrealms/world/
├── character_gen.ex                     # NEW  pure deterministic default generation (policy only)
├── level_curve.ex                       # DELETE — superseded by Srd.Rules.Experience
├── stats.ex                             # EDIT for_player/1 → adapter over Srd.Character.derive/1;
│                                        #      banding untouched
├── player.ex                            # EDIT +character fields, −mana; CreateCharacter execute/apply;
│                                        #      PlayerSpawned stops seeding stats; Experience swap
├── commands/create_character.ex         # NEW
├── events/character_created.ex          # NEW
├── commands.ex                          # EDIT +ensure_character/1 facade (:strong)
├── router.ex                            # EDIT +CreateCharacter → Player
├── projections/player_state_projector.ex# EDIT +CharacterCreated clause
├── schemas/player_state.ex              # EDIT +7 character fields, −mana/max_mana,
│                                        #      −019 placeholder stat defaults
└── seed.ex                              # EDIT orchard quest reward 100 → 300

priv/repo/migrations/
└── <ts>_add_srd_character_columns.exs   # NEW  +slugs/size/proficiency arrays, −player mana

lib/agenticrealms_web/
├── components/game/player_modals.ex     # EDIT stats_modal → three tabs; JS show/hide; no mana
├── components/game/primitives.ex        # EDIT stats_panel: drop mana bar; species/class in heading
├── live/game_live.ex                    # EDIT mount: +ensure_character/1 before spawn
└── live/game_live/ui_events.ex          # EDIT stats_changed/2: re-read on level change,
                                         #      patch via Srd.Rules.Experience otherwise
assets/css/game.css                      # EDIT sheet tab strip + panel styles

test/agenticrealms/world/                # NEW character_gen_test, stats_sheet_test,
                                         #     player_create_character_test,
                                         #     player_state_projector_character_test
                                         # EDIT player_award_xp_test (SRD thresholds, level 20 cap)
                                         # DELETE level_curve_test
test/agenticrealms_web/                  # NEW character_sheet_test (tabs, no mana, live level-up)
```

**Structure Decision**: The existing single Phoenix app plus the in-repo `packages/srd_5e` library, now linked by a path dependency.

The dividing line is rules versus policy. Every SRD calculation lives in the package, including the composition that turns a character's facts into a full sheet. The game owns what the SRD does not decide: persistence, the *choices* generation makes among legal options, and display. `Srd.Character` holds no character record — `derive/1` takes a map and returns a map — so ADR-0004's "the package holds no character of its own" still stands, though the ADR is worth a line noting it now owns the derived layer too.

All new game code sits in the existing `AgenticRealms.World` context and follows its aggregate/command/event/projector layering — one pure module, one command/event pair, one projector clause. Cluster semantics are unchanged: per-player-stream commands and node-local UI state, with no new coordination point.

## Complexity Tracking

> No constitution violations. The feature stays within established patterns — aggregate/command/event/projector, pure modules, path dependency on our own package, and client-side UI state where the interaction is local. Table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
