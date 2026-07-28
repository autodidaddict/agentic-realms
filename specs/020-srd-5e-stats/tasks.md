---
description: "Task list for feature 020 — SRD 5e Character Stats"
---

# Tasks: SRD 5e Character Stats

**Input**: Design documents from `specs/020-srd-5e-stats/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Included and mandatory. Constitution Principle IV requires tests written alongside or before the code they cover, with `mix precommit` green before merge.

**Organization**: Grouped by user story. See [Implementation Strategy](#implementation-strategy) for the recommended build order, which is **not** strictly P1 → P2 → P3 for this feature.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel — different files, no dependency on an incomplete task
- **[Story]**: US1, US2, US3 — maps to the spec's user stories

## Purge and restage

This feature does not preserve player stats. `mix world.reset` drops and recreates both the event store and the read-model database, re-runs migrations, and reseeds. No backfill code, no compatibility defaults, no data migration. See research R8.

`ecto.reset` drops the read-model database, which holds the `players` accounts table, so accounts go with it and are re-registered. That is intended.

---

## Phase 1: Setup

**Purpose**: Wire the package in and declare the character defaults.

- [X] T001 Add `{:srd_5e, path: "packages/srd_5e"}` to the deps list in `mix.exs`, then run `mix deps.get` and confirm `mix compile` succeeds with the package on the path
- [X] T002 [P] Add the `:character_defaults` block (species `"human"`, class `"fighter"`, background `"soldier"`, size `:medium`, species_skill `:perception`, species_feat `"alert"`) to `config/config.exs` per data-model.md §6.1 — this is the single place FR-010 requires

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Every SRD calculation, in the package. Plus the read-model shape and the removal of the curve `Srd.Rules.Experience` replaces.

Most of this phase is package work, and deliberately so: the game does no SRD arithmetic, so the arithmetic and its tests belong in `packages/srd_5e`.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete. The `LevelCurve` swap in particular leaves the tree red until every call site moves.

### Package: `Srd.Rules.Experience`

- [X] T003 [P] Write `packages/srd_5e/test/srd/rules/experience_test.exs` covering every case in contracts/experience.md: all twenty thresholds mapping to their own level, each threshold minus one mapping to the level below, `level_for_xp/1` at 0 / below 0 / far past 355,000, `progress/1` at band bottom / mid-band / level 20, `threshold/1` raising outside `1..20`, and `table/0` returning twenty strictly increasing entries. `async: true`. Confirm it fails
- [X] T004 Implement `Srd.Rules.Experience` in `packages/srd_5e/lib/srd/rules/experience.ex` with `table/0`, `max_level/0`, `threshold/1`, `level_for_xp/1`, and `progress/1` exactly as contracts/experience.md specifies, including `to_next: nil` and `fraction: 1.0` at level 20

### Package: `Srd.Rules.Hitpoints` additions

- [X] T005 [P] Add `starting/2`, `per_level/2`, `maximum/3`, and `hit_dice/2` describe blocks to `packages/srd_5e/test/srd/rules/hitpoints_test.exs` per contracts/hitpoints.md — every SRD hit die at positive, zero, and negative Constitution, the floor at 1, `maximum/3` across several levels, `hit_dice/2` returning an `Expr` counted by level, and notation and `Srd.Dice.Expr` accepted interchangeably. Confirm it fails
- [X] T006 Implement `starting/2`, `per_level/2`, `maximum/3`, and `hit_dice/2` in `packages/srd_5e/lib/srd/rules/hitpoints.ex`, leaving the existing pool functions untouched

### Package: supporting primitives

Each is a small addition to a module that already exists, and each needs a test in that module's existing test file. All four are independent.

- [X] T007 [P] Add `all/0` (canonical `[:str, :dex, :con, :int, :wis, :cha]`), `name/1` (`:str` → `"Strength"`), and `standard_array/0` (`[15, 14, 13, 12, 10, 8]`) to `packages/srd_5e/lib/srd/rules/ability.ex`, with cases in `test/srd/rules/ability_test.exs`
- [X] T008 [P] Add `name/1` to `packages/srd_5e/lib/srd/rules/skill.ex` covering all eighteen skills, including the multi-word ones (`:sleight_of_hand` → `"Sleight of Hand"`, `:animal_handling` → `"Animal Handling"`), with cases in `test/srd/rules/skill_test.exs`
- [X] T009 [P] Add `modifier/3` to `packages/srd_5e/lib/srd/rules/save.ex`, mirroring `Skill.check_modifier/3`'s `(ability_modifier, proficiency, opts)` shape with `proficient?:`, with cases in `test/srd/rules/save_test.exs`
- [X] T010 [P] Add `modifier/1` to `packages/srd_5e/lib/srd/rules/initiative.ex` returning the Dexterity modifier, with a case in `test/srd/rules/initiative_test.exs`. Keep it a named function even though it is a one-liner — it is the seam the Alert feat needs

### Package: `Srd.Character`

- [X] T011 Write `packages/srd_5e/test/srd/character_test.exs` covering contracts/character-derivation.md: the level 1 default character with every output field asserted, the same character at levels 5, 9, 13, 17, and 20 against published SRD values (SC-003), list ordering and lengths (6 / 6 / 18), a caster class, explicit armor and shield routing through `ArmorClass.compute/3`, and an unknown slug raising `ArgumentError`. `async: true`. Confirm it fails
- [X] T012 Implement `Srd.Character.derive/1` in `packages/srd_5e/lib/srd/character.ex`, composing every value in the contract from `Srd.Rules.*` and `Srd.Content.*`. It stores nothing, reads nothing, and defines no character struct — a map in, a map out
- [X] T013 [P] Add the `[Unreleased]` CHANGELOG entry to `packages/srd_5e/CHANGELOG.md` covering progression, hit point maxima, the derived layer, and the new primitives
- [X] T014 [P] Amend `docs/adr/0004-character-creation-content.md` with a short note that the package now owns the derived layer as well as the content, so its "holds no character of its own" line is not read as excluding `Srd.Character`
- [X] T015 Run `mix test` in `packages/srd_5e` and confirm the whole package suite is green

### Read model

- [X] T016 Create `priv/repo/migrations/<ts>_add_srd_character_columns.exs` adding `species_slug`, `class_slug`, `background_slug`, `size` (all nullable) and `skill_proficiencies`, `save_proficiencies`, `feat_slugs` (`{:array, :string}`, `null: false, default: []`) to `player_state`, and removing its `mana` and `max_mana` columns. Do not touch `npc_clones` or `blueprints` (FR-034). No compatibility defaults — the world is purged
- [X] T017 Update `lib/agenticrealms/world/schemas/player_state.ex`: add the seven fields, drop `mana` / `max_mana`, and **remove feature 019's placeholder field defaults** (`str: 12` and the rest, `level: 1`, `hp: 10`) per data-model.md §2.2

### Retire `LevelCurve`

- [X] T018 Replace every `AgenticRealms.World.LevelCurve` call site with `Srd.Rules.Experience` — `lib/agenticrealms/world/player.ex` (`level_for_xp/1` in the `AwardXp` clause), `lib/agenticrealms/world/stats.ex` (`progress/1`), and `lib/agenticrealms_web/live/game_live/ui_events.ex` (`progress/1`) — then delete `lib/agenticrealms/world/level_curve.ex` and `test/agenticrealms/world/level_curve_test.exs`
- [X] T019 Update `test/agenticrealms/world/player_award_xp_test.exs` for the SRD thresholds (level 2 at 300, not 100), keeping the existing award, multi-level jump, zero-XP no-op, and idempotent re-award cases green

### Restage

- [X] T020 Run `mix world.reset` to drop and recreate both databases, apply the migration, and reseed. Confirm the app boots and a freshly registered account can enter the world

**Checkpoint**: The package owns every SRD calculation, including the whole derived sheet. The read model has the character columns and no player mana, and `LevelCurve` is gone. User story work can begin.

---

## Phase 3: User Story 1 — Read a real character sheet (Priority: P1) 🎯

**Goal**: Three tabs inside the existing Character Sheet modal — main stats, abilities and modifiers, spells — rendering the viewing player's own SRD character, with no mana and no mock values anywhere.

**Independent Test**: The render tests build a stats map directly and assert against it, so this story is testable without US2. To *see* it in the running app with a real character, US2 must be done first — see the Implementation Strategy note.

- [X] T021 [P] [US1] Write `test/agenticrealms/world/stats_sheet_test.exs` asserting `Stats.for_player/1` returns the full shape in data-model.md §5.4 — identity, level, `xp` with `maxed?`, hp, hit dice, AC, initiative, passive perception, six abilities, six saves, eighteen skills — and that it carries no `:mana` key. Confirm it fails
- [X] T022 [US1] Rewrite `Stats.for_player/1` in `lib/agenticrealms/world/stats.ex` as a thin adapter: read `player_state`, build the facts map, call `Srd.Character.derive/1`, and merge in the player's name and current hitpoints. No SRD arithmetic in this module. Leave `health_tier/2` and `relative_power/2` untouched
- [X] T023 [P] [US1] Write `test/agenticrealms_web/character_sheet_test.exs` covering contracts/character-sheet.md: all three panels in the DOM with main visible, the main tab's ten detail values, 6 + 6 + 18 rows on the abilities tab with signed modifiers, the spells placeholder with no spell markup, and a case-insensitive assertion that `mana` appears nowhere in the sheet or sidebar. Confirm it fails
- [X] T024 [US1] Add the tab strip and three panels to `stats_modal` in `lib/agenticrealms_web/components/game/player_modals.ex`, switching with `Phoenix.LiveView.JS` show/hide and no `phx-click` to the server, with `role="tablist"` / `role="tab"` / `aria-selected` / `role="tabpanel"` and main selected on open
- [X] T025 [US1] Build the main tab in `player_modals.ex`: identity line reading `Level N · Human Fighter`, the Health and Experience bars, and the detail grid (AC, initiative, proficiency, passive perception, speed, size, hit dice, background). Guard the level 20 case so `to_next: nil` never reaches `hp_bar`'s division
- [X] T026 [US1] Build the abilities tab in `player_modals.ex`: six ability rows, six saving throw rows, and eighteen skill rows in alphabetical order, each with an explicitly signed modifier and a proficiency mark conveyed by both a filled dot and an `aria-label`, never by color alone
- [X] T027 [US1] Build the spells tab in `player_modals.ex` as a single muted placeholder reading "Spellcasting is not yet available.", matching the empty-inventory style, with no spell data or headings
- [X] T028 [US1] Add the signed-modifier formatting helper (`+0` for zero, never a bare `0` or `+-1`) to `lib/agenticrealms_web/components/game/primitives.ex` and use it from both the sheet and the sidebar
- [X] T029 [US1] Update `stats_panel` in `primitives.ex`: remove the mana bar, keep Health and Experience, and change the `who-class` line to `Level N Human Fighter`
- [X] T030 [P] [US1] Add the sheet tab strip and panel styles to `assets/css/game.css`, ensuring the strip wraps rather than clips at narrow widths
- [X] T031 [US1] Remove `player_stats/0` and `ability_scores/0` from `lib/agenticrealms/game_data.ex` if feature 019 left them, and delete the module if nothing else references it
- [X] T032 [US1] Grep the whole of `lib/agenticrealms_web/` for `mana` (case-insensitive) and confirm the only surviving hit is the unused `kind="mp"` variant of `hp_bar`, which is deliberately kept for the spells milestone

**Checkpoint**: The sheet renders three tabs from real character data, with no mana and no mock values.

---

## Phase 4: User Story 2 — Start as a complete, valid character (Priority: P2)

**Goal**: Every new player gets a deterministic Human Fighter with a Soldier background, created through the aggregate with no prompt and no interactive step.

**Independent Test**: Register a fresh account, enter the world, and read `player_state` — it carries species, class, background, the standard array plus background increases, both proficiency sets, and derived-consistent hitpoints. Registering twice produces identical stats.

- [X] T033 [P] [US2] Write `test/agenticrealms/world/character_gen_test.exs` asserting `CharacterGen.default/1` returns exactly the character in data-model.md §6.3 (STR 17 / DEX 13 / CON 15 / INT 12 / WIS 10 / CHA 8, HP 12, skills Acrobatics + Athletics + History + Intimidation + Perception, saves STR + CON, feats `savage-attacker` + `alert`), that two calls are identical, and that a non-default class config produces a correspondingly different character. DB-free. Confirm it fails
- [X] T034 [US2] Implement `AgenticRealms.World.CharacterGen` in `lib/agenticrealms/world/character_gen.ex` as a pure function of config, following the six generation steps in data-model.md §6.2, including the skill-ordering rule that applies background skills before the class picks so nothing is wasted on a duplicate
- [X] T035 [P] [US2] Create the `CreateCharacter` command in `lib/agenticrealms/world/commands/create_character.ex` with the fields in contracts/domain-events.md
- [X] T036 [P] [US2] Create the `CharacterCreated` event in `lib/agenticrealms/world/events/character_created.ex` with `@derive Jason.Encoder`, every command field plus `hp`, and `version: 1`
- [X] T037 [US2] Add `CreateCharacter` to the `dispatch([...], to: Player)` list in `lib/agenticrealms/world/router.ex`
- [X] T038 [P] [US2] Write `test/agenticrealms/world/player_create_character_test.exs` asserting a first `CreateCharacter` emits `CharacterCreated`, a second returns `:ok` with no event, `apply/2` sets every field, and the string-keyed `abilities` map survives a JSON round trip. Confirm it fails
- [X] T039 [US2] Update `lib/agenticrealms/world/player.ex`: add the seven character struct fields, remove `mana` / `max_mana`, add the `CreateCharacter` `execute/2` pair guarded on `species_slug: nil`, add `apply(%CharacterCreated{})` with the abilities-map normalizer, and strip the stat seeding out of `apply(%PlayerSpawned{})` so it sets `id` and `current_room_id` only
- [X] T040 [US2] Add the `ensure_character/1` facade to `lib/agenticrealms/world/commands.ex`, building the payload from `CharacterGen.default/1` and dispatching at `consistency: :strong`, returning `{:ok, :created}` or `{:ok, :already_created}` and never erroring on an already-created character
- [X] T041 [P] [US2] Write `test/agenticrealms/world/player_state_projector_character_test.exs` asserting the `CharacterCreated` clause upserts correctly whether or not `PlayerSpawned` has been handled, and that re-handling it does not reset `current_room_id`, `xp`, or `level`. Confirm it fails
- [X] T042 [US2] Add the `CharacterCreated` clause to `lib/agenticrealms/world/projections/player_state_projector.ex` as an upsert whose `on_conflict` set names only the character columns, per data-model.md §3.4
- [X] T043 [US2] Dispatch `Commands.ensure_character(player_id)` in `GameLive.mount` in `lib/agenticrealms_web/live/game_live.ex`, **before** the existing `Commands.spawn/2` call, so the `player_state` row is born complete
- [X] T044 [P] [US2] Write an integration test asserting a newly registered player reaches the world with a complete character, that `ensure_character/1` on a second mount emits nothing, and that creation-before-spawn ordering holds

**Checkpoint**: New characters are complete, deterministic, and created with no prompt. Combined with US1, the sheet now shows a real character end to end.

---

## Phase 5: User Story 3 — Derived values follow the level (Priority: P3)

**Goal**: Levelling moves proficiency bonus, maximum hitpoints, hit dice, saves, and skills, with the open sheet updating in place and level 20 capping cleanly.

**Independent Test**: Award enough experience to cross a threshold and re-read the sheet — every level-derived value has moved. Award past 355,000 and the level stops at 20 while the experience total keeps climbing.

- [X] T045 [P] [US3] Extend `test/agenticrealms/world/stats_sheet_test.exs` with a levelled character, asserting the sheet carries the new proficiency bonus, maximum hitpoints, hit dice, and updated proficient saves and skills. The SRD correctness of those numbers is already proven in the package by T011; this asserts the adapter passes level through and does not cache
- [X] T046 [P] [US3] Extend `test/agenticrealms/world/player_award_xp_test.exs` with the level 20 cap: an award past 355,000 emits `PlayerXpAwarded` with the new total and no `PlayerLeveledUp`, and the level stays at 20 (FR-029)
- [X] T047 [P] [US3] Change the orchard quest reward from `"xp" => 100` to `"xp" => 300` in `lib/agenticrealms/world/seed.ex`, updating the adjacent comment to say 300 lands a fresh player exactly at level 2 (FR-031)
- [X] T048 [P] [US3] Write a test asserting `UIEvents.stats_changed/2` replaces the whole `:stats` assign when `leveled_to` is present and patches from the payload without a database read when it is not. Confirm it fails
- [X] T049 [US3] Update `stats_changed/2` in `lib/agenticrealms_web/live/game_live/ui_events.ex` to re-read `Stats.for_player/1` on a level change and keep patching from the payload via `Srd.Rules.Experience.progress/1` on an XP-only change, per contracts/character-sheet.md
- [X] T050 [US3] Render the maxed case in `player_modals.ex` and `primitives.ex`: `Fully levelled` in place of `N xp to level L+1`, and a full experience bar, whenever `xp.maxed?` is true

**Checkpoint**: All three stories are functional. Levelling is SRD-correct end to end.

---

## Phase 6: Polish & Validation

- [X] T051 [P] Confirm examine is untouched and still leaks nothing — health tier and relative power only, across every band, for both players and NPCs (FR-025, FR-035)
- [X] T052 [P] Confirm `npc_clones` and `blueprints` are byte-for-byte unchanged by this branch's migration and that no NPC code path was edited (FR-034)
- [X] T053 Run `mix world.reset` and walk the full `quickstart.md` — all three stories, the level 20 cap, the config-change check that proves nothing is hardcoded, and the examine check
- [X] T054 Run `mix test` in `packages/srd_5e` and confirm green
- [X] T055 Run `mix precommit` at the repository root — `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test` — and confirm green. This is the merge gate (Principle IV)

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — **blocks all user stories**
- **US1 (Phase 3)**: depends on Foundational. Testable alone; needs US2 for a live demo
- **US2 (Phase 4)**: depends on Foundational. Fully independent
- **US3 (Phase 5)**: depends on Foundational. T045 needs T022; the rest are independent
- **Polish (Phase 6)**: depends on every story you intend to ship

### Story dependencies

US2 and US3 are genuinely independent of each other and of US1. US1 is independently *testable* — its render tests build a stats map directly — but not independently *demonstrable*, because a sheet needs a character to show. The spec says as much in its US2 priority note.

### Within Phase 2

Phase 2 is now mostly package work, and it fans out widely.

`T003 → T004` and `T005 → T006` are independent test-then-implement pairs. `T007` through `T010` are four independent primitives, each in its own module and test file, and none depends on the others.

`T011 → T012` is the composition pair, and `T012` is the one real convergence point: it needs `T004`, `T006`, and all four primitives. `T013` and `T014` are documentation and depend on nothing. `T015` gates the whole package.

On the game side, `T016 → T017` is the read-model pair. `T018` needs `T004`, and `T019` follows it. `T020` needs `T016` and `T017`.

### Within the stories

Test tasks come before the implementation they cover and must fail first. Everything touching `player_modals.ex` (T024 → T027, T050) is sequential — same file. Same for `primitives.ex` (T028 → T029, T050) and `player.ex` (T039).

---

## Parallel Opportunities

**Phase 2 opens very wide** — the package tasks touch six separate modules:

```text
Track A (package rules):   T003 → T004        Experience
                           T005 → T006        Hitpoints
                           T007               Ability primitives
                           T008               Skill.name/1
                           T009               Save.modifier/3
                           T010               Initiative.modifier/1
                                ↓ all converge
                           T011 → T012        Srd.Character.derive/1
                           T013, T014         CHANGELOG, ADR note (anytime)
                                ↓
                           T015               package suite green

Track B (read model):      T016 → T017        migration, schema
Track C (curve retirement) T018 → T019        needs T004 only
```

Six of the ten package tasks can run at once.

**Phase 3, at the start:**

```text
T021  Stats.for_player/1 shape test
T023  character sheet render test
T030  tab strip CSS
```

**Phase 4, at the start:**

```text
T033  CharacterGen test
T035  CreateCharacter command
T036  CharacterCreated event
T038  aggregate test
T041  projector test
```

**Phase 5** is almost fully parallel — T045, T046, T047, and T048 touch different files and have no ordering between them.

---

## Implementation Strategy

### Build US2 before US1

The phases are numbered by spec priority, but the useful build order for this feature is **Foundational → US2 → US1 → US3**.

US1 is the payoff and correctly P1: the sheet is what a player sees. But a sheet needs a character, and US2 is what makes one. Building US2 first means US1's work is verified against real data from the first render instead of against a fixture, and it costs nothing, because US2 has no dependency on US1.

If you would rather follow priority order strictly, US1 is still completable — its render tests inject a stats map — you will just be looking at an empty character in the browser until US2 lands.

### MVP

**Foundational + US2 + US1.** That is the smallest thing worth showing: a real, complete SRD character on a real, tabbed sheet.

US3 is worth having and is where the SRD correctness claims get proven at every proficiency band, but the feature demos without it, because a new character never levels during a demo.

### Incremental delivery

1. Phases 1–2 → every SRD rule is in the package with its own suite green, the read model is reshaped, nothing is visible yet
2. Phase 4 (US2) → characters exist and are correct, verifiable in `psql` or IEx
3. Phase 3 (US1) → the sheet shows them; this is the demo
4. Phase 5 (US3) → levelling is proven correct across the whole table
5. Phase 6 → reset, walk the quickstart, green the gate

---

## Notes

- **No SRD arithmetic in the game.** If a task has you computing a modifier, a bonus, a maximum, or a threshold anywhere under `lib/agenticrealms/`, it belongs in the package instead. The game reads rows, makes choices among legal options, and renders.
- The world is purged, not migrated. Do not write backfill code, compatibility defaults, or "characters created before this feature" test paths.
- `mix precommit` treats warnings as errors. Deleting `LevelCurve` leaves unused aliases behind if T018 is done carelessly.
- The package has its own suite. `mix precommit` at the root does not run it — T054 is a separate gate.
- Commit per task or per logical group, with no AI attribution in any message (Principle V).
