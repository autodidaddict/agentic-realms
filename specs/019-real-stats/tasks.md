---
description: "Task list for Real Stats — Players & NPCs (feature 019)"
---

# Tasks: Real Stats — Players & NPCs

**Input**: Design documents from `specs/019-real-stats/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/, research.md, quickstart.md

**Tests**: INCLUDED — the project constitution's Principle IV (Test-First, Green-Before-Merge) is NON-NEGOTIABLE. Each pure module, aggregate `execute`/`apply`, projector, handler, and integration path has a test task written **before** its implementation. `mix precommit` (compile --warnings-as-errors, format, test) is the merge gate.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3) so each is independently implementable and testable.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 / US2 / US3 (user-story phases only; Setup/Foundational/Polish have no story label)
- All paths are repository-relative.

---

## Phase 1: Setup

**Purpose**: Start from green on the feature branch (existing Elixir/Phoenix app — no scaffolding needed).

- [x] T001 Confirm baseline `mix precommit` is green on branch `019-real-stats` before any change.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared data model + pure/read modules that ≥2 user stories depend on.

**⚠️ CRITICAL**: No user story work begins until this phase is complete.

**Read-model schema (data-model §5.1):**

- [x] T002 Create migration `priv/repo/migrations/<ts>_add_stats_columns.exs` adding stat columns with SQL defaults: `player_state` (+`str,dex,con,int,wis,cha`=12, `level`=1, `xp`=0, `hp,max_hp,mana,max_mana`=10), `npc_clones` (same minus `xp`), `blueprints` (`str..cha`=12, `level`=1, `max_hp,max_mana`=10).
- [x] T003 [P] Add stat `field`s to `lib/agenticrealms/world/schemas/player_state.ex`.
- [x] T004 [P] Add stat `field`s to `lib/agenticrealms/world/schemas/npc_clone.ex`.
- [x] T005 [P] Add base stat `field`s to `lib/agenticrealms/world/schemas/blueprint.ex`.

**Level curve (pure — test-first):**

- [x] T006 [P] Unit test `test/agenticrealms/world/level_curve_test.exs`: `threshold/1` (0/100/300/600/1000), `level_for_xp/1` boundaries (0→1, 99→1, 100→2, 1000→5), `progress/1` fraction. MUST fail first.
- [x] T007 Implement `lib/agenticrealms/world/level_curve.ex` (`threshold/1`, `level_for_xp/1`, `progress/1`; `@a 50`, `@b -50`, `@c 0`) to green (T006).

**Player aggregate base stats + spawn defaults (test-first):**

- [x] T008 [P] Unit test `test/agenticrealms/world/player_spawn_stats_test.exs`: `apply(%PlayerSpawned{})` yields defaults (abilities 12, level 1, xp 0, hp 10/10, mana 10/10). MUST fail first.
- [x] T009 Add stat fields to `World.Player` defstruct and set defaults in `apply(%PlayerSpawned{})` in `lib/agenticrealms/world/player.ex` (per data-model §2.1–2.2) to green (T008).

**Player read-model init on spawn (test-first):**

- [x] T010 [P] Test `test/agenticrealms/world/player_state_projector_stats_test.exs` (part 1): `PlayerSpawned` writes default stat columns to `player_state`. MUST fail first.
- [x] T011 Extend `PlayerStateProjector.handle(%PlayerSpawned{})` in `lib/agenticrealms/world/projections/player_state_projector.ex` to seed stat columns (idempotent `on_conflict`) to green (T010).

**Character-sheet read (shared by US1 & US2, test-first):**

- [x] T012 [P] Unit test `test/agenticrealms/world/stats_for_player_test.exs`: `Stats.for_player/1` returns the sheet shape (contracts/read-and-display) with new-player defaults. MUST fail first.
- [x] T013 Implement `lib/agenticrealms/world/stats.ex` `for_player/1` (reads `player_state`, uses `LevelCurve.progress/1`; abilities list with derived modifier) to green (T012).

**Checkpoint**: Data model + level curve + player defaults + character-sheet read are in place. User stories can begin.

---

## Phase 3: User Story 1 — A real character sheet (Priority: P1) 🎯 MVP

**Goal**: The sidebar HUD card and Character modal render the player's real, persisted stats; all mock stat elements are gone.

**Independent Test**: Register a new player, open the Character Sheet → real username, Level 1, empty XP-to-next bar, HP 10/10, Mana 10/10, all abilities 12; no class, no "Veyr of Ashfall", no mana flavor captions, no "560 xp to level 8" (SC-001, SC-002).

### Tests for User Story 1

- [x] T014 [P] [US1] Render test `test/agenticrealms_web/live/character_sheet_render_test.exs`: new-player sheet shows real defaults and contains **no** mock values (class pill, deity lore, "Veyr", "Channel Dawnlight"). MUST fail first.

### Implementation for User Story 1

- [x] T015 [US1] Wire `lib/agenticrealms_web/live/game_live.ex` `mount/3` (line ~196) to `assign(:stats, Stats.for_player(player_id))`, replacing `GameData.player_stats()`.
- [x] T016 [US1] Update `stats_panel/1` in `lib/agenticrealms_web/components/game/primitives.ex`: real name + sigil (first letter of name), remove the class pill, render HP/Mana/Experience `hp_bar`s from real stats (XP bar `cur: into_level, max: to_next`).
- [x] T017 [US1] Update `stats_modal/1` in `lib/agenticrealms_web/components/game/player_modals.ex`: use `@stats.abilities` (drop `GameData.ability_scores/0`), remove class + deity lore + "Channel Dawnlight"/"Regenerates slowly" captions, compute the "N xp to level L+1" caption from progress.
- [x] T018 [US1] Remove now-unreferenced `player_stats/0` and `ability_scores/0` from `lib/agenticrealms/game_data.ex`.

**Checkpoint**: MVP — the character sheet is fully real and testable on its own.

---

## Phase 4: User Story 2 — Earn experience and level up from quests (Priority: P2)

**Goal**: Completing a quest awards its XP to the Player aggregate, which re-levels against the curve and notifies the player; the sheet updates live.

**Independent Test**: Complete the seeded orchard quest (100 XP) → XP total +100, Level 2, chat shows "You gain 100 experience." and "You are now level 2!"; sub-threshold reward shows only the XP line; NPCs never gain XP (SC-003, SC-004, SC-009).

### Tests for User Story 2

- [x] T019 [P] [US2] Aggregate test `test/agenticrealms/world/player_award_xp_test.exs`: `execute(AwardXp)` adds XP + emits `PlayerXpAwarded`; multi-level jump; `amount ≤ 0` no-op; duplicate `award_id` → no event (idempotent); `PlayerLeveledUp` only when level rises. MUST fail first.
- [x] T020 [P] [US2] Test `test/agenticrealms/world/quest_xp_threading_test.exs`: `finalize_quest/2` reads `reward["xp"]` → `QuestCompleted.xp`; `FinalizeQuest.reward_xp` threaded. MUST fail first.
- [x] T021 [P] [US2] Handler test `test/agenticrealms/world/xp_awarder_test.exs`: `QuestCompleted{xp>0}` → `award_xp` dispatched; `xp ≤ 0`/absent → no-op. MUST fail first.
- [x] T022 [P] [US2] Integration test `test/agenticrealms_web/live/xp_levelup_flow_test.exs`: quest completion updates `player_state` xp/level and emits both notices; sub-threshold emits only the XP notice. MUST fail first.

### Implementation for User Story 2

- [x] T023 [P] [US2] Create command `lib/agenticrealms/world/commands/award_xp.ex` (`%AwardXp{player_id, amount, award_id, source}`).
- [x] T024 [P] [US2] Create event `lib/agenticrealms/world/events/player_xp_awarded.ex` (`player_id, amount, new_total, award_id`).
- [x] T025 [P] [US2] Create event `lib/agenticrealms/world/events/player_leveled_up.ex` (`player_id, from_level, to_level`).
- [x] T026 [US2] In `lib/agenticrealms/world/player.ex`: add `applied_award_ids` MapSet (+ extend the `Jason.Encoder`/`JsonDecoder` impls like `discovered_room_ids`); implement `execute(%AwardXp{})` (idempotent/zero no-op; emit `PlayerXpAwarded` + conditional `PlayerLeveledUp` via `LevelCurve`) and `apply/2` for both events (T007, T023–T025).
- [x] T027 [US2] Add `AwardXp` to the `dispatch([...], to: Player)` list in `lib/agenticrealms/world/router.ex`.
- [x] T028 [US2] Add `award_xp/3` facade (dispatch `consistency: :strong`) to `lib/agenticrealms/world/commands.ex`.
- [x] T029 [P] [US2] Add `reward_xp` to `lib/agenticrealms/world/commands/finalize_quest.ex`; add `xp` (default 0) to `lib/agenticrealms/world/events/quest_completed.ex`.
- [x] T030 [US2] Thread `reward_xp` from `FinalizeQuest` into the emitted `%QuestCompleted{xp}` in `lib/agenticrealms/world/quest.ex` (T029).
- [x] T031 [US2] In `finalize_quest/2` (`lib/agenticrealms/world/commands.ex`, ~line 747) read `reward["xp"] || 0` and pass `reward_xp` into `%FinalizeQuest{}` (T029).
- [x] T032 [US2] Create handler `lib/agenticrealms/world/progression/xp_awarder.ex` (named `Commanded.Event.Handler`, `:eventual`) and register it in `lib/agenticrealms/application.ex` next to `NpcMinds.LifecycleManager` (T028).
- [x] T033 [US2] Extend `PlayerStateProjector` (`lib/agenticrealms/world/projections/player_state_projector.ex`): `handle(%PlayerXpAwarded{})` sets `xp`; `handle(%PlayerLeveledUp{})` sets `level`. Extend the projector test with these clauses (T010 file).
- [x] T034 [US2] Add `%PlayerStatsChanged{player_id, stats, xp_gained, leveled_to}` to `lib/agenticrealms/world/ui_events.ex`; witness `PlayerXpAwarded`/`PlayerLeveledUp` in `lib/agenticrealms/world/ui_event_broadcaster.ex` → broadcast it (with refreshed `Stats.for_player/1`) on `Topics.player_topic(player_id)`.
- [x] T035 [US2] Add `handle_info(%PlayerStatsChanged{})` in `lib/agenticrealms_web/live/game_live.ex` → new `stats_changed/2` in `lib/agenticrealms_web/live/game_live/ui_events.ex`: `assign(:stats, ...)` + `append_log` `:system` notices ("You gain N experience.", and on level-up "You are now level M!").
- [x] T036 [US2] Add `"xp" => 100` to the orchard quest `reward` map in `lib/agenticrealms/world/seed.ex` (`orchard_quests`).

**Checkpoint**: XP + leveling + notices work end-to-end from the seeded quest; US1 sheet updates live.

---

## Phase 5: User Story 3 — Size up a target by examining it (Priority: P3)

**Goal**: Examining a player or NPC appends a health-tier sentence and a relative-power phrase; NPCs carry real stats frozen at spawn; no exact numbers leak.

**Independent Test**: `examine <npc>` shows a health tier + power phrase; a same-level NPC reads "about as powerful", a ≥4-levels-higher NPC "too powerful to even compare", a low-HP NPC a low tier; no ability/level/XP/mana numbers appear; `examine me` omits the power phrase (SC-005, SC-006).

### Tests for User Story 3

- [x] T037 [P] [US3] Unit test `test/agenticrealms/world/stats_banding_test.exs`: `health_tier/2` cutoffs (≥90/65–89/35–64/10–34/<10, 0→"At death's door") and `relative_power/2` bands (±4 extremes, −1..+1 same). MUST fail first.
- [x] T038 [P] [US3] Projector test `test/agenticrealms/world/entity_projector_npc_stats_test.exs`: `EntityCloned{fields with stats}` writes stat columns to `npc_clones`; `hp == max_hp` at spawn; two clones of one blueprint have independent rows. MUST fail first.
- [x] T039 [P] [US3] Examine test `test/agenticrealms/world/examine_stats_test.exs`: examine of NPC and of player each append a health tier + power phrase, leak no exact numbers, and self-examine omits the power phrase. MUST fail first.

### Implementation for User Story 3

- [x] T040 [P] [US3] Add pure `health_tier/2` and `relative_power/2` to `lib/agenticrealms/world/stats.ex` (T037).
- [x] T041 [US3] Freeze NPC stats at spawn: add stat keys to the `fields` map in `spawn_npc_clone_row/3` (from blueprint) and `spawn_npc_freeform/3` (defaults) in `lib/agenticrealms/world/commands.ex` (data-model §5.3).
- [x] T042 [US3] Write frozen stat columns from `fields` (via `fval/2`; `hp := max_hp`, `mana := max_mana`) in `EntityProjector.insert_npc/2` (`lib/agenticrealms/world/projections/entity_projector.ex`) (T038, T041).
- [x] T043 [P] [US3] Add `:health_tier` and `:power_phrase` fields to `lib/agenticrealms/world/examine/match.ex`.
- [x] T044 [US3] In `lib/agenticrealms/world/examine.ex`: load the examiner's level in scope; populate `:health_tier`/`:power_phrase` in `npc_match/1` and `player_match/1` (skip power on self) using `Stats.health_tier/2` + `Stats.relative_power/2` (T040, T043).
- [x] T045 [US3] Render the two lines: carry `health_tier`/`power_phrase` into the `:detail` entry in `look_target/4` (`lib/agenticrealms_web/live/game_live/player_commands.ex`) and render them in the npc + player branches of `lib/agenticrealms_web/components/game/log_entry.ex` (never exact numbers).
- [~] T046 [P] [US3] (Seed exercise) author a seeded NPC clone with `hp < max_hp` — **DEFERRED**. Directly writing `npc_clones` in the seed would bypass the projector (violates Event-Sourcing Principle II), and authoring non-default NPC stats properly requires extending the blueprint-authoring command chain (out of this milestone's scope). Seeded NPCs correctly take default stats (level 1, full HP) via the read-model column defaults; non-full tiers are exercised by `examine_stats_test` / `stats_banding_test` and reproducible by wounding an NPC in IEx. The `npc_clones`/`blueprints` stat columns are in place for the follow-up.

**Checkpoint**: All three stories independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T047 [P] Grep to confirm no lingering mock stat references remain (`GameData.player_stats`, `GameData.ability_scores`, "Veyr of Ashfall", "Channel Dawnlight") anywhere in `lib/`.
- [x] T048 [P] Run `specs/019-real-stats/quickstart.md` end-to-end (real sheet → orchard quest level-up → examine tiers → logout/login persistence).
- [x] T049 Run `mix precommit` (warnings-as-errors, format, full test) — must be green (the merge gate).

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (P1)** → no deps.
- **Foundational (P2)** → after Setup; **blocks all user stories**. Internal order: T002 before T003–T005 (columns exist); T006→T007; T008→T009; T010→T011; T012→T013 (T013 uses T007).
- **US1 (P3)** → after Foundational. Delivers the MVP.
- **US2 (P4)** → after Foundational. Reuses the foundational `Stats.for_player/1` (T013); its live sheet-refresh (T034–T035) integrates with US1's `:stats` assign (T015), but the award/level/notify core (T019–T033, T036) is independently testable.
- **US3 (P5)** → after Foundational (needs `npc_clones`/`blueprints` columns T004–T005 and `player_state` columns for player targets). Independent of US1/US2.
- **Polish (P6)** → after the desired stories are done.

### Within each user story

- Tests (the `MUST fail first` tasks) precede their implementation.
- Command/event structs (T023–T025, T029) before the aggregate logic that uses them (T026, T030).
- Aggregate/handler before the projector/broadcast that observe their events.

---

## Parallel Opportunities

- **Foundational**: T003/T004/T005 together; T006 and T008 and T010 and T012 (test files) together.
- **US2 tests**: T019/T020/T021/T022 together. **US2 structs**: T023/T024/T025/T029 together.
- **US3 tests**: T037/T038/T039 together. T040 and T043 and T046 are parallel-safe.
- Once Foundational is done, **US1 / US2 / US3 can be staffed in parallel** (US2's UI live-update lands cleanest after US1).

### Parallel example — Foundational test-first

```bash
Task: "Unit test level_curve_test.exs"            # T006
Task: "Unit test player_spawn_stats_test.exs"     # T008
Task: "Test player_state_projector_stats_test.exs"# T010
Task: "Unit test stats_for_player_test.exs"       # T012
```

---

## Implementation Strategy

### MVP first (US1 only)

1. Phase 1 Setup → 2. Phase 2 Foundational (CRITICAL) → 3. Phase 3 US1 → **STOP & VALIDATE**: the character sheet is fully real (defaults, no mock). Demo-able MVP.

### Incremental delivery

- Foundational + US1 → real sheet (MVP).
- + US2 → XP/leveling from quests + live notices.
- + US3 → examine health/mettle + NPC stats.
- Each story adds value without breaking the previous.

---

## Notes

- `[P]` = different files, no dependency on an incomplete task.
- Every `MUST fail first` test is written and confirmed red before its implementation (Principle IV).
- Reseed (`mix ecto.reset`) after T002/T036/T041/T046 rather than data-migrate (event log destroyable pre-launch).
- Commit after each task or logical group; keep commits attribution-free (Principle V).
- No new runtime dependency is introduced anywhere in this feature.
