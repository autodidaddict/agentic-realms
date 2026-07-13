# Implementation Plan: Real Stats — Players & NPCs

**Branch**: `019-real-stats` | **Date**: 2026-07-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/019-real-stats/spec.md`

## Summary

Give every player and NPC first-class stats — six ability scores (STR/DEX/CON/INT/WIS/CHA), a level, current/max hitpoints, current/max mana, and (players only) experience — replacing the hardcoded mock character sheet in `AgenticRealms.GameData`. Three player-facing slices:

1. **A real character sheet** (P1): the sidebar HUD card and the Character modal render the viewing player's actual persisted stats; all mock elements (class, deity lore, hardcoded "V" sigil, "560 xp to level 8", mana flavor captions) are removed or made dynamic.
2. **XP & leveling from quests** (P2): quests carry an experience reward; completing one awards XP to the **Player aggregate**, which re-evaluates level against a compounding-quadratic curve and emits a level-up when a threshold is crossed. The player is notified in the log.
3. **Examine reveals condition & mettle** (P3): examining a player or NPC appends a health-tier sentence (band of % max HP) and a relative-power phrase (band of level delta vs. the examiner), never leaking exact numbers.

**Key design decisions (Phase 0):**

1. **Player stats are aggregate-owned; NPC stats are read-model-only (frozen at spawn).** Players' level/XP change during play, so they live on the `World.Player` aggregate as event-sourced state (like `discovered_room_ids`). NPC stats never mutate this milestone (no damage yet), so they are frozen onto the `npc_clones` row at spawn via the existing `EntityCloned{fields}` full-copy denormalization — **no NPC aggregate stat events, no NPC event-shape change** (stats ride inside the generic `fields` map).
2. **XP is awarded by a named `Commanded.Event.Handler`, mirroring feature 018's `LifecycleManager`.** A new `World.Progression.XpAwarder` subscribes to `QuestCompleted{xp: n}` and dispatches `AwardXp` to the Player aggregate — an exclusive single cluster-wide subscriber, so exactly one node awards each quest's XP (Principle I) with **no new Horde singleton**.
3. **Award is idempotent per source via an `award_id` MapSet on the aggregate**, reusing the exact idempotency pattern already proven by `discovered_room_ids`/`RecordRoomDiscovery`. At-least-once redelivery of `QuestCompleted` cannot double-award.
4. **The level curve is a pure module** (`World.LevelCurve`), a compounding quadratic `XP(L) = 50·L² − 50·L` (thresholds 0/100/300/600/1000…), unbounded. Health-tier and relative-power banding are pure functions in `World.Stats`. All three are DB-free and unit-tested first (Principle IV).
5. **No new runtime dependency.** Reuses Commanded/Ecto, the existing witness → PubSub → LiveView pipeline (`UIEventBroadcaster` → `Topics.player_topic` → `handle_info` → `append_log`), the existing `hp_bar` meter component (its `kind="xp"` variant already exists), and the `:system` log kind for notices.

## Technical Context

**Language/Version**: Elixir ~1.20 (OTP), Phoenix 1.8 / LiveView 1.1
**Primary Dependencies**: Commanded 1.4.x + commanded_eventstore_adapter + eventstore (PostgreSQL), Ecto/Postgrex 3.13, Phoenix.PubSub. **No new dependency.**
**Storage**: Two PostgreSQL databases — event store (`AgenticRealms.EventStore`) and read model (`AgenticRealms.Repo`). **One read-model migration** adding stat columns to `player_state`, `npc_clones`, and `blueprints`. No event-store migration (event log is destroyable pre-launch; reseed not migrate).
**Testing**: ExUnit; `AgenticRealms.DataCase` (Ecto SQL Sandbox + `@moduletag :commanded`). Pure logic (`LevelCurve`, `Stats` banding, aggregate `execute`/`apply`) unit-tested without the DB; projector/handler/examine paths use the established `:commanded` + sandbox harness.
**Target Platform**: Linux server; multi-node BEAM cluster (Horde present). Cluster semantics are explicit: the XP handler is an exclusive named Commanded subscriber (cluster singleton for free); no new stateful processes.
**Project Type**: Web application (Phoenix LiveView front end + event-sourced domain backend).
**Performance Goals**: Stat reads are single indexed `Repo.get` by primary key (`player_state`/`npc_clones`). XP award is one `:strong` dispatch off the quest-completion path. Examine adds two pure banding computations plus at most one extra indexed read (examiner level). No per-tick or hot-loop work.
**Constraints**: Player XP/level MUST change only through the Player aggregate (sole writer); read models written only by projectors; XP award idempotent under redelivery/replay; examine MUST NOT leak exact ability/level/XP/mana numbers; the character sheet MUST contain zero mock values.
**Scale/Scope**: One aggregate extended (Player), one new command + two new events, one new event handler, three read-model tables extended, two pure modules, and UI edits to two stat surfaces + the examine render. ≥500 concurrent mostly-idle NPCs already targeted by 018 — stats add only columns to their existing rows.

**Unknowns resolved in Phase 0** (see `research.md`): storage shape (columns vs. jsonb), award trigger (handler vs. projector), idempotency strategy, level-curve evaluation, examine data-flow, seed XP reward wiring, mock-element replace-vs-remove. **No `NEEDS CLARIFICATION` remain** (four resolved in `/speckit.clarify`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution v1.0.0 (ratified 2026-06-09). Assessment against the six principles:

| Principle | Assessment |
|---|---|
| **I. Cluster-Correct by Default (NON-NEGOTIABLE)** | **PASS.** The one cross-aggregate reaction (award XP on quest completion) is a **named `Commanded.Event.Handler`** (`XpAwarder`) → an exclusive single cluster-wide subscriber, so exactly one node awards each quest's XP — the same primitive as 018's `LifecycleManager`. No new Horde registry/supervisor is introduced (none needed: there is no new long-lived stateful process). The Player aggregate is a per-player stream (already `identify`'d). LiveView stat assigns and the sidebar/modal are node-local socket state (correct). Duplicate delivery is handled by the aggregate's `award_id` idempotency. |
| **II. Event-Sourcing Invariants (NON-NEGOTIABLE)** | **PASS.** Player XP/level change only via the Player aggregate (sole writer): `AwardXp` → `PlayerXpAwarded` (+ conditional `PlayerLeveledUp`), state via `apply/2`. Read models (`player_state`, `npc_clones`) are written only by projectors reacting to events; the character sheet reads the projected `player_state`, never raw events. Projectors stay idempotent/replay-safe (`on_conflict`, and the award-id guard makes re-handling a no-op). NPC stats are added to the existing frozen `EntityCloned{fields}` snapshot — no new event, no ad-hoc row writes. Quest XP is denormalized onto `QuestCompleted` at finalize (the aggregate already snapshots the reward), so the handler reads the event, not un-projected data. |
| **III. Local-First LiveView Interaction** | **PASS.** New round-trips are all server-authoritative: XP/level are persisted, curve-evaluated progression broadcast cross-node to the owning player's socket (a justified round-trip, noted here per the principle). The character sheet renders from server state. No behavior that could be client-local is being sent to the server; the only client concern (which modal is open) is already local. |
| **IV. Test-First, Green-Before-Merge** | **PASS.** Pure units first: `LevelCurve` (`level_for_xp`, `threshold`, `progress`), `Stats.health_tier/2`, `Stats.relative_power/2`. Then aggregate `execute`/`apply` for `AwardXp` (award, multi-level jump, zero-XP no-op, idempotent re-award), the `PlayerStateProjector` stat clauses, the `XpAwarder` handler, the `EntityProjector` NPC-stat freeze, examine health/power additions, and the quest-XP threading. `mix precommit` (warnings-as-errors, format, test) is the gate. |
| **V. Clean Git History — No AI Attribution (NON-NEGOTIABLE)** | **PASS.** All commits on this branch omit attribution; continues. |
| **VI. Idiomatic Phoenix & Deliberate Simplicity** | **PASS.** Zero new dependencies. New logic is cohesive and small: two pure modules (`LevelCurve`, `Stats`) and one handler (`XpAwarder`) under the existing `World` context; everything else extends existing aggregates/commands/events/projectors/components. Stats are flat integer columns matching the existing `npc_clones` flat-column convention (no premature value-object abstraction). Level-up is a first-class observable event; the aggregate rebuilds stat state from its stream on restart (snapshots already enabled for Player). |

**Design elements worth flagging** (tracked in Complexity Tracking): none — the design stays entirely within established patterns. Complexity Tracking is empty.

**Post-Design re-check**: PASS — Phase 1 introduced no new machinery beyond the named handler and pure modules already assessed. No principle is bent.

## Project Structure

### Documentation (this feature)

```text
specs/019-real-stats/
├── plan.md              # This file
├── research.md          # Phase 0 — decisions & rationale (storage, award trigger, idempotency, curve eval, examine flow)
├── data-model.md        # Phase 1 — command/events, aggregate state, read-model columns + migration, curve, banding
├── quickstart.md        # Phase 1 — run the app, see a real sheet, complete the orchard quest to level up, examine an NPC
├── contracts/
│   ├── domain-events.md         # AwardXp command + PlayerXpAwarded / PlayerLeveledUp events + QuestCompleted.xp + idempotency
│   ├── read-and-display.md      # Stats.for_player shape, LevelCurve function contract, examine health/power output, notice log lines
│   └── stat-defaults.md         # Player & NPC/blueprint default stat values and the freeze-at-spawn contract
├── checklists/
│   └── requirements.md  # Spec quality checklist (present, all pass)
└── tasks.md             # Phase 2 — created by /speckit.tasks (NOT here)
```

### Source Code (repository root)

New pure `LevelCurve` + `Stats` modules and an `XpAwarder` event handler in the `World` context; a Player-owned `AwardXp` command with `PlayerXpAwarded`/`PlayerLeveledUp` events; stat columns on three read-model tables via one migration; NPC stat freeze at spawn; quest XP threading; a real `Stats.for_player` read feeding two UI surfaces; and examine additions.

```text
lib/agenticrealms/world/
├── level_curve.ex                       # NEW  pure: threshold/1, level_for_xp/1, progress/1 (quadratic 50L²−50L, unbounded)
├── stats.ex                             # NEW  pure banding: health_tier/2, relative_power/2; + for_player/1 read (character-sheet shape)
├── progression/xp_awarder.ex            # NEW  Commanded.Event.Handler (consistency: :eventual): QuestCompleted{xp>0} → Commands.award_xp/3
├── player.ex                            # EDIT +stat fields on struct; apply(PlayerSpawned) seeds defaults; execute/apply for AwardXp (+ award_id MapSet, Jason/JsonDecoder like discovered_room_ids)
├── commands/award_xp.ex                 # NEW  %AwardXp{player_id, amount, award_id, source}
├── events/player_xp_awarded.ex          # NEW  %PlayerXpAwarded{player_id, amount, new_total, award_id}
├── events/player_leveled_up.ex          # NEW  %PlayerLeveledUp{player_id, from_level, to_level}
├── commands/finalize_quest.ex           # EDIT +reward_xp field
├── events/quest_completed.ex            # EDIT +xp field (denormalized reward XP)
├── quest.ex                             # EDIT thread reward_xp from FinalizeQuest into QuestCompleted{xp}
├── commands.ex                          # EDIT finalize_quest/2 reads reward["xp"]; +award_xp/3 facade (dispatch :strong); NPC spawn fields carry stats
├── router.ex                            # EDIT add AwardXp to dispatch([...], to: Player)
├── queries.ex                           # EDIT (or Stats) player/npc stat reads used by examine + sheet
├── examine.ex                           # EDIT load examiner level; populate Match health_tier/power_phrase for :npc and :player (skip power on self)
├── examine/match.ex                     # EDIT +:health_tier, :power_phrase fields
├── projections/player_state_projector.ex# EDIT PlayerSpawned seeds stat columns; handle PlayerXpAwarded (xp) + PlayerLeveledUp (level)
├── projections/entity_projector.ex      # EDIT insert_npc/2 writes frozen stat columns from fields (via fval)
├── schemas/player_state.ex              # EDIT +stat fields
├── schemas/npc_clone.ex                 # EDIT +stat fields
├── schemas/blueprint.ex                 # EDIT +base stat fields (npc kind)
├── ui_events.ex                         # EDIT +%PlayerStatsChanged{} (+ xp_gained / leveled_to for the notice)
├── ui_event_broadcaster.ex              # EDIT witness PlayerXpAwarded/PlayerLeveledUp → broadcast PlayerStatsChanged on player_topic
└── seed.ex                              # EDIT orchard quest reward map += "xp" => 100; (optional) authored NPC blueprint stats

priv/repo/migrations/
└── <ts>_add_stats_columns.exs           # NEW  alter player_state (+xp), npc_clones, blueprints — ability scores, level, hp/max_hp, mana/max_mana

lib/agenticrealms_web/live/game_live.ex          # EDIT mount: :stats = Stats.for_player(player_id) (replaces GameData.player_stats/0); +handle_info(%PlayerStatsChanged{})
lib/agenticrealms_web/live/game_live/ui_events.ex# EDIT +stats_changed/2 (update :stats assign; append :system notice(s))
lib/agenticrealms_web/components/game/primitives.ex   # EDIT stats_panel: real name/sigil; drop class pill; hp/mp/xp bars from real stats
lib/agenticrealms_web/components/game/player_modals.ex# EDIT stats_modal: drop class + lore + mana captions; dynamic "N xp to level L+1"; ability rows from real stats (replaces GameData.ability_scores/0)
lib/agenticrealms/game_data.ex                   # EDIT remove player_stats/0 and ability_scores/0 (mock stat sources) once unreferenced

test/agenticrealms/world/                 # NEW level_curve_test, stats_banding_test, player_award_xp_test (award/level/jump/zero/idempotent), player_state_projector_stats_test, xp_awarder_test, entity_projector_npc_stats_test, examine_stats_test, quest_xp_threading_test
test/agenticrealms_web/                    # NEW character_sheet_render_test (no mock values; defaults; live update on level-up)
```

**Structure Decision**: Single Phoenix app. All domain logic lives in the existing `AgenticRealms.World` context — two pure modules (`LevelCurve`, `Stats`), one Player-owned command/event pair, and one named event handler (`Progression.XpAwarder`), reusing the aggregate/command/event/projector layering and the witness → PubSub → LiveView pipeline. Player stats are event-sourced aggregate state; NPC stats are frozen read-model data carried in the existing `EntityCloned{fields}` snapshot. Cluster semantics: the XP handler is an exclusive Commanded subscriber (no new singleton); everything else is per-player-stream or node-local UI.

## Complexity Tracking

> No constitution violations. This feature introduces no deviations requiring justification — it stays within existing patterns (aggregate/command/event/projector, named event handler, pure modules, witness/PubSub/LiveView, flat read-model columns, reseed-not-migrate). Table intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
