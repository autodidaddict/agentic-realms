---
description: "Task list for 021-character-creation"
---

# Tasks: Interactive Character Creation

**Input**: Design documents from `specs/021-character-creation/`
**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/)

**Tests**: Included, and not optional here. Constitution Principle IV (Test-First, Green-Before-Merge) is NON-NEGOTIABLE: every aggregate `execute`/`apply`, projector, context function, and integration path must have tests written alongside or before the implementation, and `mix precommit` is the merge gate.

**Organization**: Grouped by user story so each ships alone. Until a story's phase lands, `CharacterGen.complete/1` fills the choices that story would ask for (research R9, data-model §6), so every checkpoint is a playable game.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1–US5, mapping to the spec's five user stories
- Every task names its exact file path

## Path Conventions

Two projects, both at the repository root:

- **Rules library**: `packages/srd_5e/lib/`, `packages/srd_5e/test/`
- **Game**: `lib/agenticrealms/`, `lib/agenticrealms_web/`, `test/`, `priv/repo/migrations/`

---

## Phase 1: Setup

**Purpose**: A known-green baseline before anything moves.

- [X] T001 Confirm the baseline is green on this branch: `mix precommit` at the repository root, and `mix test` in `packages/srd_5e`
- [X] T002 [P] Open an `## [Unreleased]` entry in `packages/srd_5e/CHANGELOG.md` for `Srd.Character.choices/1`, `Srd.Character.grants/1`, and the `:size` choice kind

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The package API, the read-model columns, and the pure modules every story sits on. Nothing here is visible to a player.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Rules library

- [X] T003 [P] Add `:size` to `@kinds` in `packages/srd_5e/lib/srd/content/choice.ex` and extend its `@type kind`
- [X] T004 [P] Write failing tests for `Srd.Character.choices/1` in `packages/srd_5e/test/srd/character_choices_test.exs` per [contracts/character-choices.md](./contracts/character-choices.md): all nine species, twelve classes and four backgrounds; the four species with no lineage return no `:species_lineage`; human returns `:species_size` and the eight single-size species do not; fighter at level 1 returns Fighting Style and Weapon Mastery and never a subclass; a `Choice.fixed?/1` choice (acolyte's tool) is absent; partial selections and `%{}`
- [X] T005 [P] Write failing tests for `Srd.Character.grants/1` in `packages/srd_5e/test/srd/character_grants_test.exs`: outright skills, saves, feats, the background's raisable abilities, and features through level; a feat granted twice appears once; lists sorted
- [X] T006 Implement `Srd.Character.choices/1` in `packages/srd_5e/lib/srd/character.ex` — walks species sizes/lineages/features, class skill_choice/tool_proficiency/features, and background tool, omitting fixed and above-level choices, returning `%{key:, source:, label:, text:, choice:}` in the documented order (depends on T003, T004)
- [X] T007 Implement `Srd.Character.grants/1` in `packages/srd_5e/lib/srd/character.ex`, deduplicated and sorted (depends on T005)
- [X] T008 Run `mix test` in `packages/srd_5e` and confirm green (depends on T006, T007)

### Read model

- [X] T009 [P] Create `priv/repo/migrations/<ts>_add_character_name_and_choices.exs` adding `character_name` (string, nullable — see data-model.md §2), `lineage_slug` (string, nullable), `choices` (map, `null: false`, `default: %{}`) to `player_state`, plus a non-unique index on `lower(character_name)` named `player_state_character_name_lower_idx`
- [X] T010 Add `character_name`, `lineage_slug`, and `choices` fields to `lib/agenticrealms/world/schemas/player_state.ex` (depends on T009)

### Pure game modules

- [X] T011 [P] Write failing tests in `test/agenticrealms/world/player_names_test.exs`: `get/1` returns `nil` before creation and the name after; `find_by_name/1` matches regardless of case; `get_many/1` returns a map keyed by player id
- [X] T012 Implement `lib/agenticrealms/world/player_names.ex` reading `player_state.character_name` (depends on T010, T011)
- [X] T013 [P] Write failing tests in `test/agenticrealms/world/character_draft_test.exs`: construction; changing species/class/background clears exactly the dependent entries per data-model.md §1; changing the name clears nothing; step reachability
- [X] T014 Implement `lib/agenticrealms/world/character_draft.ex` with the struct and invalidation expressed as "drop every entry whose key is no longer in `Srd.Character.choices/1`", not as a dependency table (depends on T006, T013)
- [X] T015 [P] Write failing tests in `test/agenticrealms/world/character_draft_validator_test.exs` covering every row of data-model.md §7, including forged submissions: a pick not in the offered options, too many picks, an ability outside the background's three, a non-permutation of the standard array, a name of 33 characters. Include a test that an *incomplete* draft fails — the validator has no "skip if empty" clause, and completing the draft is the facade's job
- [X] T016 Implement `lib/agenticrealms/world/character_draft/validator.ex` as set membership against `Srd.Character.choices/1` and `grants/1` — it must contain no SRD rule of its own, and every rule is unconditional because it only ever sees a completed draft (data-model.md §6, §7) (depends on T007, T014, T015)

### LiveView refactor

- [X] T017 Extract everything `mount/3` does from `Commands.spawn/2` onward into a private `enter_world/1` in `lib/agenticrealms_web/live/game_live.ex` — spawn, `look_room`, inventory, presence, the PubSub subscriptions, `fire_for_arrival`, and the assigns. Pure refactor: no behavior change, existing suite stays green
- [X] T018 Run `mix precommit` and confirm green (depends on T010, T012, T014, T016, T017)

**Checkpoint**: The package answers what is open, the columns exist, the draft and validator work, and mount is split. Nothing player-visible has changed.

---

## Phase 3: User Story 1 - Name and identity (Priority: P1) 🎯 MVP

**Goal**: A player with no character gets a modal, names their character, picks a species, class, and background, and enters the world as that character. The name is unique across the cluster and is what other players see.

**Independent Test**: Register a new account, click Play, complete the dialog, and verify the sheet shows the chosen name, species, class, and background with a complete legal character; then verify a second player in the same room sees the character name and never the username, and that the same name cannot be claimed twice.

### Tests for User Story 1

> Write these first and confirm they fail.

- [X] T019 [P] [US1] Name-collision tests in `test/agenticrealms/world/create_character_facade_test.exs`: a name another character already holds is refused with `{:error, :name_taken}`, matching regardless of case and ignoring surrounding whitespace, and nothing is written to the player's stream. **Not** tested: that a same-instant race is prevented — FR-013 permits it, and research R2 records why the machinery that would prevent it was removed
- [X] T020 [P] [US1] Extend `test/agenticrealms/world/player_create_character_test.exs`: the three new fields round-trip onto `CharacterCreated`; a second `CreateCharacter` still emits nothing; `lineage_slug: nil` round-trips; and FR-031 — changing `:character_defaults` after creation leaves an existing character unchanged, because the event carries finished values rather than a reference to the configuration
- [X] T021 [P] [US1] Extend `test/agenticrealms/world/player_state_projector_character_test.exs`: the three new columns set on insert and on conflict; FR-030 — a created character is level 1 with zero experience and `hp == max_hp`; a redelivered event still does not reset `level`/`xp`/`current_room_id`; a `PlayerSpawned`-first replay does not crash on a null `character_name`
- [X] T022 [P] [US1] Facade tests in `test/agenticrealms/world/create_character_facade_test.exs`: **a draft carrying only a name, species, class, and background — the US1 shape — completes and creates a legal character**; a draft whose choices the player did make is not overwritten by completion; the happy path creates exactly one character; an invalid draft dispatches nothing at all; a second `create_character/2` for a player who already has one creates no second character
- [X] T023 [P] [US1] Dialog tests in `test/agenticrealms_web/live/character_creation_dialog_test.exs` for the identity step: a player with no character sees the dialog and one with a character does not; **the dialog renders no close button, no click-catching backdrop, and no Escape binding, and cannot be dismissed by any of the three**; confirm unavailable until a name and all three selections exist, and the dialog says what is missing; species/class/background detail rendered from content; the class card states the subclass level without offering one; a taken name keeps the dialog open with every choice intact; disconnecting leaves no `player_state` row
- [X] T024 [P] [US1] Concurrent-confirmation test in `test/agenticrealms_web/live/character_creation_dialog_test.exs`: two live sessions for one player both reach the dialog and both confirm; exactly one character exists and the second session is carried into the world rather than shown an error (FR-004, SC-007, and the spec's two-tab edge case)
- [X] T025 [P] [US1] Rewrite `test/agenticrealms_web/live/character_creation_test.exs` — it currently asserts the generated default arrives with no prompt, which is the behavior this story removes; it becomes the interactive mount path

### Write side

- [X] T026 [P] [US1] *(removed)* A `ClaimCharacterName` command is no longer needed — names are checked, not reserved (research R2)
- [X] T027 [P] [US1] *(removed)* No `ReleaseCharacterName` — one dispatch, so there is nothing to compensate
- [X] T028 [P] [US1] *(removed)* No `CharacterNameClaimed` event
- [X] T029 [P] [US1] *(removed)* No `CharacterNameReleased` event
- [X] T030 [US1] *(removed)* No `CharacterName` aggregate. It was built, reviewed against the cost of the two-phase creation it forces, and removed; research R2 names the reservation-table design to reach for if strict uniqueness is ever wanted
- [X] T031 [US1] *(removed)* `lib/agenticrealms/world/router.ex` is unchanged by this feature
- [X] T032 [US1] Add `character_name`, `lineage_slug`, and `choices` to `lib/agenticrealms/world/commands/create_character.ex`
- [X] T033 [US1] Add the same three to `lib/agenticrealms/world/events/character_created.ex` (depends on T032)
- [X] T034 [US1] Carry the three new fields through `CreateCharacter`'s `execute`/`apply` in `lib/agenticrealms/world/player.ex`, leaving the "emit only when `species_slug` is unset" guard unchanged (depends on T020, T033)
- [X] T035 [US1] Add the three new fields to the `identity` list of the `CharacterCreated` clause in `lib/agenticrealms/world/projections/player_state_projector.ex`, leaving `seeded` untouched (depends on T021, T033)
- [X] T036 [US1] Add `complete/1` to `lib/agenticrealms/world/character_gen.ex` per data-model.md §6: takes a `%CharacterDraft{}` and returns one with every open decision settled, filling **only what is missing** so a player's choice is never overwritten. Fills `array`, `spread`, `skill_picks`, and any key in `Srd.Character.choices/1` with no entry. Does **not** fill species, class, or background — those are story 1's, and their absence is a validation error rather than something to guess at. Stays pure and deterministic (depends on T006, T014, T032)
- [X] T037 [US1] Implement `Commands.create_character/2` in `lib/agenticrealms/world/commands.ex` — **complete, validate, check the name, create `:strong`** — and replace `ensure_character/1` with a public `has_character?/1` that `GameLive` mounts on. Completing before validating is what lets a story ship alone; without it nothing can be created until US4. One dispatch, so a failure leaves no trace and needs no compensation. Land this together with T042, which removes the last caller of `ensure_character/1` (depends on T016, T022, T034, T036)

### Dialog

- [X] T038 [US1] Add `attr :dismissable, :boolean, default: true` to `modal/1` in `lib/agenticrealms_web/components/game/primitives.ex`, guarding all three ways out when false: the `phx-window-keydown="close_modal"` Escape binding, the full-bleed `phx-click="close_modal"` div, and the `✕` button. The four existing modals keep the default and are unchanged. FR-002 cannot be met without this, and leaving the bindings in place would render controls that silently do nothing, since `close_modal` only clears the `@modal` assign the creation dialog does not use
- [X] T039 [US1] Create `lib/agenticrealms_web/components/game/character_creation.ex` with the modal shell (`dismissable={false}`), the step strip rendered from shipped steps, and the identity step: name field plus species, class, and background option cards showing the detail FR-017 requires, all sourced from `Srd.Content` (depends on T007, T038)
- [X] T040 [US1] Register the new component in `lib/agenticrealms_web/components/game_components.ex` (depends on T039)
- [X] T041 [US1] Create `lib/agenticrealms_web/live/game_live/creation.ex` with the `creation_name`, `creation_select`, `creation_step`, and `creation_confirm` handlers per [contracts/creation-dialog.md](./contracts/creation-dialog.md) (depends on T014, T037)
- [X] T042 [US1] Add the `:phase` assign to `lib/agenticrealms_web/live/game_live.ex`, branch `mount/3` on `PlayerNames.get/1` in place of the deleted `ensure_character/1`, and delegate the creation events to `GameLive.Creation`. Land together with T037 — that task deletes the function this one stops calling (depends on T012, T017, T041)
- [X] T043 [US1] Branch `lib/agenticrealms_web/live/game_live.html.heex` on `@phase`: `:creating` renders the app shell with an inert game pane and the creation modal; `:playing` renders exactly what it renders today (depends on T039, T042)
- [X] T044 [US1] Add the debounced name availability check (400 ms) to `GameLive.Creation`, backed by an indexed `PlayerNames` query, setting `name_status` (depends on T012, T041)
- [X] T045 [P] [US1] Add the creation dialog styles to `assets/css/game.css`: step strip, option card grid that scrolls within the dialog body, name field states

### Identity: the character name replaces the username

Every seam is enumerated in [contracts/player-identity.md](./contracts/player-identity.md).

- [X] T046 [P] [US1] `lib/agenticrealms/world/queries.ex` — `list_players_in_room/1` and `list_other_players/2` select and order by `ps.character_name`, dropping the join to `accounts.players`; the returned map key becomes `:name`
- [X] T047 [P] [US1] `lib/agenticrealms/world/stats.ex` — `player_name/1` reads `character_name` off the `player_state` row already loaded, removing the `Accounts` query
- [X] T048 [P] [US1] `lib/agenticrealms/world/ui_event_broadcaster.ex` — `lookup_username/1` becomes a `PlayerNames.get/1` lookup, and the payload key becomes `actor_name`
- [X] T049 [P] [US1] `lib/agenticrealms/world/examine.ex` — `acting_username/1`, `player_match/1`, and both matchers move to `:name`
- [X] T050 [US1] `lib/agenticrealms/world/ui_events.ex` — rename `actor_username` to `actor_name` on every event struct (depends on T048)
- [X] T051 [US1] `lib/agenticrealms/world/communication.ex` and `lib/agenticrealms/world/communication/recipient_resolver.ex` — sender map carries `:name`, broadcasts `actor_name`, and recipients resolve via `PlayerNames.find_by_name/1` (depends on T012, T050)
- [X] T052 [P] [US1] `lib/agenticrealms/world/npc_chat/context.ex` and `lib/agenticrealms/world/intent_resolver/context_snapshot.ex` — character name in the LLM context and the resolver snapshot
- [X] T053 [P] [US1] `lib/agenticrealms/world/wizard_trance.ex` — rename `wizard_username` to `wizard_name`
- [X] T054 [US1] `lib/agenticrealms_web/presence.ex` — `track_player/3` tracks `%{name: ...}`; `lib/agenticrealms_web/live/game_live.ex` passes the character name (depends on T042)
- [X] T055 [US1] Web consumers of the renamed keys: `lib/agenticrealms_web/live/game_live/ui_events.ex`, `lib/agenticrealms_web/live/game_live/communication.ex`, `lib/agenticrealms_web/components/game/log_entry.ex`, `lib/agenticrealms_web/components/game/primitives.ex`, `lib/agenticrealms_web/components/game/player_modals.ex` (depends on T050, T051, T054)
- [X] T056 [P] [US1] `lib/agenticrealms_web/controllers/npc_service_controller.ex` — source the name from Queries' `:name` key; the published JSON shape is unchanged, so `specs/018-external-npc-api/contracts/npc-service-api.md` needs no edit (depends on T046)
- [X] T057 [US1] Update every affected test across `test/agenticrealms/world/` and `test/agenticrealms_web/live/` to character names — rooms, communication, examine, presence, NPC API. Map-key renames get no help from the compiler, so this suite is the net (depends on T046–T056)
- [X] T058 [US1] Add the SC-012 assertion somewhere a second player can observe the first: register with one username, create a character with a different name, and assert the username appears nowhere in what the other player is rendered (depends on T057)
- [X] T059 [US1] Run `mix world.reset && mix ecto.migrate`, then `mix precommit`, then the integration tests with `mix test --include integration` (depends on T025, T037, T044, T045, T058)

**Checkpoint**: US1 is complete and playable. A player names their character, picks a species, class, and background, and enters a world where that name is their identity. Ability scores, skills, and specializations are still filled by `CharacterGen.complete/1`.

---

## Phase 4: User Story 2 - Ability scores and background bonuses (Priority: P2)

**Goal**: The player assigns the standard array and chooses how the background's increases are spread.

**Independent Test**: Create a character, assign the array in a non-default order, choose a +2/+1 spread, confirm, and verify the sheet's six scores equal the assigned values plus the chosen increases with every dependent value following.

- [X] T060 [P] [US2] Extend `test/agenticrealms/world/character_draft_test.exs`: assigning a value already held swaps the two abilities; changing the background clears the spread and leaves the array
- [X] T061 [P] [US2] Extend `test/agenticrealms_web/live/character_creation_dialog_test.exs`: only the background's three abilities are offered; the `[1,1,1]` spread asks nothing further; each ability shows its final score and modifier including the increase; no score exceeds 20 (defensive — unreachable at level 1, where the array tops out at 15 and the largest increase is +2)
- [X] T062 [US2] Add array assignment with swap-on-collision and spread selection to `lib/agenticrealms/world/character_draft.ex` (depends on T060)
- [X] T063 [US2] Add the abilities step to `lib/agenticrealms_web/components/game/character_creation.ex`: the six-value assignment grid and the spread selector over `Background.spreads/0` and `grants/1`'s `abilities`, showing final scores and modifiers (depends on T007, T062)
- [X] T064 [US2] Add `creation_assign_ability` and `creation_spread` handlers to `lib/agenticrealms_web/live/game_live/creation.ex` (depends on T062)
- [X] T065 [US2] Assert in `test/agenticrealms/world/character_gen_test.exs` that `complete/1` leaves a player-supplied `array` and `spread` untouched, and that `CharacterGen.default/0` still generates both for the seed and test path. Nothing is deleted here: `complete/1` fills only what is missing, so once the dialog supplies these the fill stops firing on its own, and removing it would break the seeds (research R9) (depends on T064)
- [X] T066 [P] [US2] Add the ability grid styles to `assets/css/game.css`
- [X] T067 [US2] Run `mix precommit` and the integration tests (depends on T063, T064, T065)

**Checkpoint**: US1 and US2 both work. Skills and specializations still filled by completion.

---

## Phase 5: User Story 3 - Skill proficiencies (Priority: P3)

**Goal**: The player picks the skills their class offers, with granted skills shown and never spendable.

**Independent Test**: Create a character as a class offering a skill choice, pick a set different from what completion would pick, confirm, and verify the sheet marks exactly those plus the granted ones.

- [X] T068 [P] [US3] Extend `test/agenticrealms/world/character_draft_test.exs`: changing the class clears the picks and keeps name, species, and background
- [X] T069 [P] [US3] Extend `test/agenticrealms_web/live/character_creation_dialog_test.exs`: exactly the class' number of picks from exactly its list; a background-granted skill shows as held and cannot consume a pick; selecting past the limit is refused or releases an earlier pick; the overlap case still reaches a complete character
- [X] T070 [US3] Add skill picking to `lib/agenticrealms/world/character_draft.ex`, excluding anything in `grants/1`'s `skills` (depends on T007, T068)
- [X] T071 [US3] Add the skills step to `lib/agenticrealms_web/components/game/character_creation.ex`, showing each option's keying ability and the modifier the character would have (depends on T070)
- [X] T072 [US3] Add the `creation_pick` handler for skills to `lib/agenticrealms_web/live/game_live/creation.ex`, respecting `choose` (depends on T070)
- [X] T073 [US3] Assert in `test/agenticrealms/world/character_gen_test.exs` that `complete/1` leaves player-supplied `skill_picks` untouched, and that `default/0` still picks skills for the seed and test path. Same reasoning as T065 — no code is removed (depends on T072)
- [X] T074 [P] [US3] Add the skill list styles to `assets/css/game.css`
- [X] T075 [US3] Run `mix precommit` and the integration tests (depends on T071, T072, T073)

**Checkpoint**: US1–US3 work. Specializations still filled by completion.

---

## Phase 6: User Story 4 - Species and class specializations (Priority: P4)

**Goal**: Every level 1 choice a species or class carries, rendered generically from `Srd.Character.choices/1`.

**Independent Test**: Create an elf and see an Elven Lineage question; create a dwarf and see the step skipped entirely; create a fighter and see Fighting Style and three Weapon Masteries.

- [X] T076 [P] [US4] Extend `test/agenticrealms_web/live/character_creation_dialog_test.exs`: elf shows a lineage and dwarf shows none; human shows a size question and elf does not; fighter shows Fighting Style and Weapon Mastery; changing species or class discards that source's picks; a selection combination with no open choices skips the step; **a feat the background already granted is shown as held and cannot be picked again** — a human whose background grants Alert cannot spend Versatile on Alert (FR-027 and the spec's duplicate-feat edge case)
- [X] T077 [P] [US4] Add persistence assertions to `test/agenticrealms/world/player_state_projector_character_test.exs`: `lineage_slug` and the `choices` map round-trip through the event to the row
- [X] T078 [US4] Add the specializations step to `lib/agenticrealms_web/components/game/character_creation.ex` — one renderer dispatching on `choice.kind` across `:lineage`, `:size`, `:feat`, `:weapon`, `:tool`, `:feature`, and `:skill`, with no code naming any specific choice. `:feat` and `:skill` choices filter out anything already in `grants/1` and label it "already granted by your background", the same treatment the skills step gives a granted skill, so a duplicate is visible rather than silently deduplicated at creation (depends on T006, T007)
- [X] T079 [US4] Extend the `creation_pick` handler in `lib/agenticrealms_web/live/game_live/creation.ex` to the generic keyed choices (depends on T078)
- [X] T080 [US4] Map the draft's picks onto the command in `lib/agenticrealms/world/commands.ex`: `:species_lineage` to `lineage_slug`, `:feat`-kind picks into `feat_slugs`, `:skill`-kind picks into `skill_proficiencies`, and everything else into `choices` (depends on T037, T079)
- [X] T081 [US4] Assert in `test/agenticrealms/world/character_gen_test.exs` that `complete/1` leaves player-supplied lineage, size, and feature choices untouched, and that on a fully-answered draft it is now a no-op — every fill still exists and none of them fires. `default/0` continues to generate a whole character for the seed and test path (depends on T080)
- [X] T082 [P] [US4] Add the option-card and multi-select styles to `assets/css/game.css`, verifying the ten-lineage dragonborn grid scrolls within the dialog body
- [X] T083 [US4] Verify FR-009 by hand per [quickstart.md](./quickstart.md): add a lineage to a species that has none in `packages/srd_5e/priv/data/species.exs`, recompile, see it in creation with no game change, then revert (depends on T078)
- [X] T084 [US4] Run `mix precommit` and the integration tests (depends on T078, T079, T080, T081)

**Checkpoint**: US1–US4 work. Every SRD level 1 choice is the player's.

---

## Phase 7: User Story 5 - Review before committing (Priority: P5)

**Goal**: The whole character before it exists, computed by the same function and rendered by the same components as the character sheet.

**Independent Test**: Step through creation, open the review, go back and change the class, return, and verify hit die, hitpoints, saving throws, and class features all follow.

- [X] T085 [P] [US5] Extend `test/agenticrealms_web/live/character_creation_dialog_test.exs`: the review's numbers equal `Srd.Character.derive/1` on the same facts; going back and changing a choice updates the review without redoing unrelated choices; confirm is unavailable while anything is incomplete and the review names the incomplete step; the created character equals what the review showed
- [X] T086 [US5] Add `facts/1` to `lib/agenticrealms/world/character_draft.ex`, producing the map `Srd.Character.derive/1` takes. It operates on a **completed** draft — call `CharacterGen.complete/1` first, or accept only a completed one — because `derive/1` raises on missing abilities and a draft is incomplete whenever a story before this one has not shipped (depends on T014, T036)
- [X] T087 [US5] Add the review step to `lib/agenticrealms_web/components/game/character_creation.ex`, rendering the **completed** draft through the same panel components `stats_modal` uses in `lib/agenticrealms_web/components/game/player_modals.ex`, plus the features and feats from `grants/1` and the completed draft's picks. Rendering anything less would break FR-029, since what gets created is the completed draft (depends on T086)
- [X] T088 [US5] Gate confirm on the validator and surface which step is incomplete in `lib/agenticrealms_web/live/game_live/creation.ex`. Run the validator against the *completed* draft so the review shows what will actually be created, and report only errors on fields the player owns (depends on T016, T036, T087)
- [X] T089 [P] [US5] Add the review panel styles to `assets/css/game.css`, reusing the character sheet's panel treatment
- [X] T090 [US5] Run `mix precommit` and the integration tests (depends on T087, T088)

**Checkpoint**: All five stories work independently.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T091 [P] Finalize the `packages/srd_5e/CHANGELOG.md` `[Unreleased]` entry against what actually shipped
- [X] T092 [P] Add a short note to `docs/adr/0004-character-creation-content.md` recording that the package gained `choices/1` and `grants/1` in feature 021 and that the ADR's line is unchanged — options out, nothing held (research R1)
- [X] T093 Audit `:character_defaults` in `config/config.exs`: confirm every key still has a reader in `CharacterGen.default/0` or the seed and test path, and remove only genuine orphans. `complete/1` keeps all its fills, so expect few or none — this is a check, not a cleanup with a known outcome
- [X] T094 Grep `lib/` for remaining `username` references and confirm every survivor is on the authentication path — `accounts.ex`, `accounts/player.ex`, `player_auth.ex`, `player_session_controller.ex`, and the three auth LiveViews
- [X] T095 Walk [quickstart.md](./quickstart.md) end to end, including the two-node uniqueness check and the abandon-leaves-nothing check
- [X] T096 Final gate: `mix world.reset && mix ecto.migrate`, `mix test` in `packages/srd_5e`, `mix precommit`, and `mix test --include integration` at the root

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: depends on Setup — **blocks every user story**
- **US1 (Phase 3)**: depends on Foundational
- **US2–US5 (Phases 4–7)**: depend on Foundational and on US1, because every later story adds a step to the dialog US1 creates and takes over a decision `CharacterGen.complete/1` was making on the player's behalf
- **Polish (Phase 8)**: depends on every story that is being shipped

### User Story Dependencies

This feature's stories are **sequential, not parallel**, and that is a deliberate consequence of the spec's design rather than a flaw in it. Each story after the first adds a step to the same modal and takes over a decision `complete/1` was making, so they share `character_creation.ex` and `creation.ex`. They remain independently *testable* and independently *shippable* — the point of the ordering is that stopping after any one of them leaves a playable game — but they are not independently *developable* in parallel by different people without conflicting in three files.

- **US1 (P1)**: after Foundational. No dependency on any other story
- **US2 (P2)**: after US1
- **US3 (P3)**: after US1. Independent of US2 in principle; touches the same three files
- **US4 (P4)**: after US1. Independent of US2 and US3 in principle; touches the same three files
- **US5 (P5)**: after US1, and most valuable after US4, since there is little to review until the choices exist

### Tasks that must land together

- **T037 and T042**: T037 deletes `ensure_character/1`; T042 is the last caller. Split across commits, the tree does not compile in between.

### Within Each Story

Tests first and failing, then the write side, then the dialog, then the `complete/1` hand-over assertion, then the gate.

`complete/1` is written once, in US1, and never edited again. Later stories do not remove its fills; they simply stop leaving gaps for it to fill, and assert as much. The fills stay because `CharacterGen.default/0` still needs them for seeds and tests (research R9).

---

## Parallel Opportunities

### Phase 2 (Foundational)

The package work and the read-model work are independent:

```text
T003  Add :size to Choice
T004  choices/1 tests
T005  grants/1 tests
T009  Migration
T011  PlayerNames tests
T013  CharacterDraft tests
T015  Validator tests
```

T004 and T005 edit different test files; T006 and T007 both edit `character.ex`, so they are sequential.

### Phase 3 (US1)

Seven test files and test groups, all independent:

```text
T019  Facade name-collision tests
T020  Player aggregate tests
T021  Projector tests
T022  Facade tests
T023  Dialog tests
T024  Concurrent-confirmation test
T025  Rewritten mount test
```

Seven of the identity seams touch files nothing else in the phase touches:

```text
T046  queries.ex
T047  stats.ex
T048  ui_event_broadcaster.ex
T049  examine.ex
T052  npc_chat/context.ex + intent_resolver/context_snapshot.ex
T053  wizard_trance.ex
T056  npc_service_controller.ex
```

T050, T051, T054, and T055 are sequential behind them because they consume the renamed keys. T038 must precede T039, since the component cannot pass an attribute the shell does not accept.

### Phases 4–7

Only the CSS task in each phase is parallelizable; everything else in a story queues on the same three files.

---

## Implementation Strategy

### MVP (User Story 1 only)

1. Phase 1: Setup
2. Phase 2: Foundational — blocks everything
3. Phase 3: US1
4. **Stop and validate**: a new player names their character, picks a species, class, and background, and enters a world where that name is their identity. Ability scores, skills, and specializations are filled by `complete/1`.
5. Ship it.

That is already the feature's main value: players stop being identical copies of one another, and the world stops calling them by their login.

### Incremental delivery

| After | A player can |
|---|---|
| Foundational | nothing new — internal only |
| US1 | name their character and pick a species, class, and background |
| US2 | decide what their character is good at |
| US3 | decide what their character is trained in |
| US4 | make every level 1 choice the SRD offers |
| US5 | see the whole character before committing to it |

Each row is a deployable increment, and none breaks the row above it. `CharacterGen.complete/1` is what makes the rows above US4 possible: it fills what the dialog has not learned to ask.

### Sizing

US1 is the largest phase, at 41 of the 96 tasks (six of which turned out to be unnecessary once the uniqueness aggregate was dropped), and roughly a third of that is the identity rename. That concentration is deliberate: the rename lands with the name it depends on rather than being spread across later stories, and it is the one part of the feature the compiler cannot check, so it wants a single focused pass with the test suite as the net.

---

## Notes

- `[P]` means a different file with no dependency on incomplete work
- Every story's phase ends with a green `mix precommit`, per Principle IV
- The world is purged and restaged rather than migrated (`mix world.reset`); the event log is destroyable in the current phase
- Commit after each task or logical group; no AI attribution in any commit or PR (Principle V)
