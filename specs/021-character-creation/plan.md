# Implementation Plan: Interactive Character Creation

**Branch**: `021-character-creation` | **Date**: 2026-08-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/021-character-creation/spec.md`

## Summary

Replace feature 020's configuration-generated character with a modal the player drives, and make
the name they choose their identity in the world.

Two things happen. The `srd_5e` package learns to answer "what does this character still have to
decide?", so the dialog can ask a question the game has never heard of. And the world stops reading
`accounts.players.username`, because the character name is now what other players see.

Five slices, matching the spec's five stories:

1. **Name and identity** (P1). The modal appears when a player has no character, takes a name and a
   species, class, and background, and creates the character. Everything the SRD still allows is
   filled in by the generation that runs today. This is also where the name becomes the player's
   public identity, because that is part of having a name at all.
2. **Ability scores** (P2). The standard array is assigned by the player, and the background's
   increases are spread the way they choose.
3. **Skill proficiencies** (P3). The class' picks become the player's, with granted skills shown.
4. **Specializations** (P4). Lineage, size, and every level 1 feature choice a class or species
   carries, driven generically by what the package returns.
5. **Review** (P5). The whole character before it exists, computed by `Srd.Character.derive/1` —
   the same function the character sheet already calls, so the review cannot disagree with it.

**Key design decisions (Phase 0, full rationale in [research.md](./research.md)):**

1. **The package answers what is still open.** `Srd.Character.choices/1` returns every open
   pick-N-of-M decision for a species, class, and background at a level; `grants/1` returns what
   they grant outright. This is what makes FR-006 and FR-009 hold, and it needs no ADR-0004
   amendment: selections in, options out, holding nothing.
2. **Names are checked, not reserved.** The facade asks the projection whether a name is taken and
   refuses if so. A `CharacterName` aggregate was built and removed: a character is keyed by its
   player rather than its name, so making the name a stream costs a *second* aggregate and turns
   creation into a two-phase commit with a compensating command and a claim that outlives a dying
   node. That is a lot of machinery to prevent a same-millisecond collision whose consequence is
   cosmetic. FR-013 was relaxed instead.
3. **One dispatch, nothing to compensate.** Complete, validate, check the name, create.
4. **No unique index on the projection.** Duplicates are a permitted outcome, and a unique
   constraint would turn one into a halted projector — a worse failure than the collision itself.
5. **The draft is node-local socket state**, never persisted, never broadcast. Selections cost a
   round trip because they buy the next step's options out of compile-time content, which is the
   Principle III case for server authority rather than an exception to it.
6. **`GameLive` gains a `:creating` phase**, and everything mount does after a character exists
   moves into `enter_world/1`. The creating phase renders an inert pane behind the modal rather
   than making thirty assigns nil-tolerant.
7. **Validation is set membership, not rules.** The facade re-asks the package what was legal and
   checks each pick against the answer, so the game validates a fighting style without knowing what
   one is.
8. **`CharacterGen` stays** and gains `complete/1`. The facade completes a draft *before* validating
   it, which is what lets a story ship alone: a draft carrying only a name, species, class, and
   background arrives at the validator as a whole character. `ensure_character/1` goes away.
9. **The world stops reading usernames.** One lookup, `World.PlayerNames`, plus a rename of the
   world-facing keys from `username` to `name` and `actor_username` to `actor_name`.
10. **No new runtime dependency**, no new aggregate, no new process, no new Horde registry, and no
    new coordination point of any kind.

## Technical Context

**Language/Version**: Elixir ~1.20 (OTP), Phoenix 1.8 / LiveView 1.1
**Primary Dependencies**: Commanded 1.4.x + commanded_eventstore_adapter + eventstore
(PostgreSQL), Ecto/Postgrex 3.13, Phoenix.PubSub, and the in-repo `{:srd_5e, path:
"packages/srd_5e"}` path dependency feature 020 added. **No new dependency.**
**Storage**: The two existing PostgreSQL databases. **One read-model migration** adding
`character_name`, `lineage_slug`, and `choices` to `player_state`, plus a non-unique index on
`lower(character_name)`. No event-store migration: the event log is destroyable pre-launch, so the
extended `CharacterCreated` simply starts appearing and the world is reseeded.
**Testing**: ExUnit in both projects. The package carries the content walking and therefore most of
the pure tests — `Srd.Character.choices/1` and `grants/1` across all nine species, twelve classes,
and four backgrounds, all `async: true` and DB-free. In the game, `CharacterDraft` and its
validator are DB-free unit tests; the extended `Player` aggregate, the projector clause, the facade,
and the modal use the established
`AgenticRealms.DataCase` harness (Ecto SQL Sandbox + `@moduletag :commanded`), with the full mount
path under `@moduletag :integration` as `character_creation_test.exs` already is.
**Target Platform**: Linux server; multi-node BEAM cluster (Horde present). No new coordination
point: the draft is per-socket state on the node holding that socket, and the name check is a plain
read of the projection. Cluster semantics are exactly what they were.
**Project Type**: Web application (Phoenix LiveView front end + event-sourced domain backend) plus
the in-repo pure Elixir rules library.
**Performance Goals**: One round trip per selection, each one a compile-time content read and a
struct update with no database access. The availability check is one indexed query, debounced. The
review is one `Srd.Character.derive/1` call, roughly forty integer operations. Confirmation is one
strongly-consistent dispatch plus the existing spawn. Nothing per-tick, nothing in a hot loop.
**Constraints**: Character state changes only through aggregates; read models written only by
projectors; the game reimplements no SRD rule and holds no SRD list; the created character equals
the reviewed character; nothing persists before confirmation; exactly one character per player; no
account username visible to another player.
**Scale/Scope**: In the package, two new functions on an existing module and one new `Choice` kind.
In the game, one command and one event extended, three new pure modules (`CharacterDraft`, its
validator, `PlayerNames`) plus `CharacterGen.complete/1`, one migration, one projector clause,
`GameLive` split into two phases, and one new modal component. Plus the
identity rename, which touches roughly twenty-eight files in `lib/` and a comparable number of
tests. One function deleted (`ensure_character/1`). NPC records, blueprints, quests, and the
external NPC API contract are untouched.

**Unknowns**: none. The spec's three `NEEDS CLARIFICATION` markers were answered during
`/speckit.specify`; research.md records the ten design questions settled in Phase 0.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution v1.0.0 (ratified 2026-06-09). Assessment against the six principles:

| Principle | Assessment |
|---|---|
| **I. Cluster-Correct by Default (NON-NEGOTIABLE)** | **PASS.** No coordination point is added at all, which the spec states explicitly. The draft is per-socket state on the node holding that socket — the node-local case the principle permits — and is never read from anywhere else. `PlayerNames` is a stateless read. `CreateCharacter` is a per-player-stream command dispatched from the player's own LiveView, exactly as `SpawnPlayer` is. The one thing that *would* have introduced a cluster-wide invariant, strictly unique names, was considered and deliberately dropped (research R2), and FR-013 records that as a decision rather than an omission. Presence tracking is unchanged apart from the value it carries. |
| **II. Event-Sourcing Invariants (NON-NEGOTIABLE)** | **PASS.** One aggregate, `Player`, still the sole writer of `player-<id>`. The command carries finished values and the aggregate looks nothing up, so replay cannot disagree with what was recorded. No write-side state lives outside the event store — the reservation table that a uniqueness guarantee would have needed was rejected partly on this ground (research R2). `player_state` stays written only by `PlayerStateProjector`; the extended `CharacterCreated` clause sets absolute values, so re-handling is a no-op, and the existing split between identity columns and seeded progression columns is preserved for the new fields. No unique constraint is added to a projection, deliberately (R3), so a projector cannot be halted by write-side state. Nothing reads raw event data. The event log is destroyable in the current phase, so the extended event shape needs no stream migration and the world is reseeded. |
| **III. Local-First LiveView Interaction** | **PASS, with the round trips stated.** Three interactions reach the server and each is justified in research R5: a selection buys the next step's options out of compile-time content the client does not have; the availability check needs the database by definition; and confirmation persists. Everything else stays local — which step is visible is server-rendered only because its content differs per step, and the feature 020 sheet tabs remain client-side and untouched. No round trip is added to any existing interaction. |
| **IV. Test-First, Green-Before-Merge** | **PASS.** Pure and DB-free first: `Srd.Character.choices/1` and `grants/1` over every species, class, and background, including the species that offer no lineage and the classes whose only level 1 choice is skills; `CharacterDraft` construction, dependent-choice invalidation on a changed selection, and the validator against both legal and forged submissions. Then the `Player` aggregate's extended `CreateCharacter`, the projector clause, the facade including the US1-shaped draft that only completion makes legal, and the modal end to end. The identity rename is covered by the existing suite, which is the point of doing it as a rename rather than a re-populate. `mix precommit` gates the app; `mix test` in the package gates the library. |
| **V. Clean Git History — No AI Attribution (NON-NEGOTIABLE)** | **PASS.** No attribution in any commit or PR on this branch. |
| **VI. Idiomatic Phoenix & Deliberate Simplicity** | **PASS, and improved during implementation.** No new dependency and — after the `CharacterName` aggregate was built, reviewed, and removed — no new aggregate, command, or event either. Creation is one dispatch through the existing `Player` aggregate. The package additions are two pure functions on a module that already exists, walking content it already carries. Deliberate omissions: no uniqueness aggregate and no reservation table (R2), no persisted draft (R5), no unique index (R3), no `Srd.Character.validate/1` (R8), no equipment (R10), no per-choice column (R7). |

**Design elements worth flagging**: the identity rename is the largest diff in the feature and the
one most likely to produce a surprise, because map keys are not caught by
`compile --warnings-as-errors`. It is bounded by the test suite rather than by the compiler, which
is why R4 lists every seam explicitly and why the rename lands in slice 1 alongside the name itself
rather than being spread across slices. It is not a constitution concern.

**Post-Design re-check**: PASS, and the design got smaller during implementation. A `CharacterName`
aggregate was built to guarantee unique names, then removed under Principle VI once the cost was
visible in code: a second aggregate, two dispatches, a compensating command, and an orphaned claim
when a node dies mid-flight, all to prevent a same-millisecond collision with a cosmetic
consequence. FR-013 was relaxed to match. Research R2 records the comparison and names the design to
reach for — a reservation table with a unique index — if the guarantee is ever genuinely needed.

## Project Structure

### Documentation (this feature)

```text
specs/021-character-creation/
├── plan.md              # This file
├── research.md          # Phase 0 — ten decisions: where "what is open" lives, name
│                        #   uniqueness, the orphan window, no unique index, the identity
│                        #   rename, the draft, rendering before a character, what is
│                        #   stored, validation, CharacterGen's fate, equipment
├── data-model.md        # Phase 1 — draft vs character, the migration, commands, events,
│                        #   aggregates, projector, and the invalidation rules
├── quickstart.md        # Phase 1 — run it, see all five stories, prove uniqueness and
│                        #   that abandoning leaves nothing
├── contracts/
│   ├── character-choices.md   # Srd.Character.choices/1 + grants/1, the choice key, :size
│   ├── domain-events.md       # why there is no new aggregate, the extended
│   │                          #   CreateCharacter/CharacterCreated, mount ordering
│   ├── creation-dialog.md     # The steps, what each shows, the round trips, the events
│   └── player-identity.md     # Every seam where username becomes the character name
├── checklists/
│   └── requirements.md  # Spec quality checklist (all pass)
└── tasks.md             # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

```text
packages/srd_5e/
├── lib/srd/character.ex                 # EDIT +choices/1, +grants/1 alongside derive/1
├── lib/srd/content/choice.ex            # EDIT +:size to @kinds
├── test/srd/character_choices_test.exs  # NEW  every species/class/background; the species
│                                        #      with no lineage; the multi-size species
├── test/srd/character_grants_test.exs   # NEW  outright grants, and no duplicates across
│                                        #      background + species + class
└── CHANGELOG.md                         # EDIT [Unreleased] entry

lib/agenticrealms/world/
├── character_draft.ex                   # NEW  the in-progress struct + invalidation
├── character_draft/validator.ex         # NEW  set membership against choices/1 + grants/1
├── player_names.ex                      # NEW  the one place the world asks a player's name
├── character_gen.ex                     # EDIT +complete/1, +payload/1 — fills only what the
│                                        #      player was not asked
├── commands/create_character.ex         # EDIT +character_name, +lineage_slug, +choices
├── events/character_created.ex          # EDIT +character_name, +lineage_slug, +choices
├── commands.ex                          # EDIT +create_character/2 (complete, validate, check
│                                        #      the name, create); −ensure_character/1
├── projections/player_state_projector.ex# EDIT CharacterCreated clause takes the new fields
├── schemas/player_state.ex              # EDIT +character_name, +lineage_slug, +choices
├── queries.ex                           # EDIT name from player_state, not accounts; :name key
├── stats.ex                             # EDIT name from the row it already read
├── examine.ex                           # EDIT match on character name
├── communication.ex                     # EDIT actor_name; sender map carries :name
├── communication/recipient_resolver.ex  # EDIT resolve by character name
├── ui_events.ex                         # EDIT actor_username → actor_name
├── ui_event_broadcaster.ex              # EDIT lookup via PlayerNames
├── npc_chat/context.ex                  # EDIT name
├── intent_resolver/context_snapshot.ex  # EDIT name
└── wizard_trance.ex                     # EDIT wizard_username → wizard_name

priv/repo/migrations/
└── <ts>_add_character_name_and_choices.exs  # NEW  +3 columns, +index on lower(name)

lib/agenticrealms_web/
├── components/game/character_creation.ex# NEW  the modal: steps, choice rendering, review
├── components/game/primitives.ex        # EDIT modal/1 +dismissable attr (FR-002 needs a way to
│                                        #      suppress the Escape, backdrop, and ✕ closes)
├── live/game_live.ex                    # EDIT :phase; extract enter_world/1; mount branches
├── live/game_live.html.heex             # EDIT branch on @phase; render the creation modal
├── live/game_live/creation.ex           # NEW  the dialog's handle_event clauses
├── live/game_live/ui_events.ex          # EDIT actor_name
├── live/game_live/communication.ex      # EDIT name
├── presence.ex                          # EDIT track the character name
└── controllers/npc_service_controller.ex# EDIT source the name from Queries' :name key
                                         #      (the published JSON shape is unchanged)
assets/css/game.css                      # EDIT creation dialog: steps, option cards, review

test/agenticrealms/world/                # NEW character_draft_test, character_draft_validator_test,
                                         #     player_names_test, create_character_facade_test
                                         # EDIT player_state_projector_character_test, queries,
                                         #     examine, communication, recipient_resolver tests
test/agenticrealms_web/                   # NEW character_creation_dialog_test (steps, validation,
                                         #     the review, abandoning)
                                         # EDIT character_creation_test.exs — it currently asserts
                                         #     the generated default; it becomes the interactive path
```

**Structure Decision**: The existing Phoenix app plus the in-repo `packages/srd_5e` library, with
no change to how they are linked.

The dividing line ADR-0004 drew holds and this feature leans on it harder than any before. The
package answers what may be chosen and what a choice grants; it never learns what was chosen. The
game owns the choosing: the draft, the validation, the persistence, and the presentation. That is
why the new package functions take slugs and return options, and why the validator in the game
knows only "was this pick in the list I was handed".

New game code sits in the existing `AgenticRealms.World` context and follows its
aggregate/command/event/projector layering. The web layer follows the existing split, with the
dialog's `handle_event` clauses in a `GameLive.Creation` helper module beside `PlayerCommands`,
`Communication`, `Wizard`, and `UIEvents`, and its markup in a component beside `PlayerModals`.

## Complexity Tracking

> No constitution violations. The one addition that read as extra machinery, a `CharacterName`
> aggregate, was built and then removed under Principle VI; research R2 records the comparison and
> FR-013 records the relaxed requirement that made it unnecessary. Table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
