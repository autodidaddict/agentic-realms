# Implementation Plan: Wizard-Created Object Blueprints (Milestone 1)

**Branch**: `014-item-blueprints` | **Date**: 2026-06-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/014-item-blueprints/spec.md`

## Summary

This feature ships the **substrate** for wizard-authored world content. It introduces:

1. **Wizard authorization** — `Accounts.Player` schema gains `is_wizard` (default `false`). A plain-Ecto `Accounts.promote_to_wizard/1` function is the only path to promotion in milestone 1 (intended to be invoked from `iex`). Every wizard-only LiveView event handler and every wizard-only Commanded command verifies `is_wizard` at entry. Non-wizards see no top-bar Wizard switch.
2. **`ObjectBlueprint` Commanded aggregate** (new) — identified by a human-typable slug per `^[a-z][a-z0-9_]*$`, prefix `"object-blueprint-"`. Holds `name`, `short_description`, `long_description`, `fixed`, and a monotonic `revision`. Owns optimistic-lock enforcement (FR-020a) at the aggregate boundary: every `EditObjectBlueprint` command carries the wizard's known revision and is refused with `{:error, :stale_revision, current_revision: N}` if it doesn't match aggregate state.
3. **`object_blueprints` read-model table** (new) — projected from `ObjectBlueprintCreated` / `ObjectBlueprintEdited` events by a new `ObjectBlueprintProjector`. The slug is the primary key (`string`, NOT NULL); `revision` is the integer counter; no `created_by` field; no `is_synthetic` flag (synthetic blueprints aren't needed since freeform clones have no blueprint at all).
4. **World-mode Object creation paths**:
   - **`SpawnObjectFromBlueprint{blueprint_id, object_id, room_id, wizard_id}`** — dispatched to the destination `Room` aggregate; the wrapper reads the blueprint's current payload at dispatch time and stamps it into the command. The aggregate emits `ObjectSpawned{object_id, room_id, name, short_description, long_description, fixed}` (no `blueprint_id` in the payload — see Q4 clarification).
   - **`SpawnObjectFreeform{object_id, room_id, wizard_id, name, short_description, long_description, fixed}`** — same destination aggregate, same emitted event (`ObjectSpawned`). The two paths converge at the event boundary; the projector is path-agnostic.
   - Both feed the existing `world_objects` table via the projector. The schema gains no new columns (the spec's FR-013 rule: no `blueprint_id` column on Object rows).
5. **In-place Object editing** — `EditObject{object_id, wizard_id, fields_changed_map}` against the existing `Room` aggregate (whichever room currently owns the object), emitting `ObjectEdited{object_id, fields...}`. The projector applies the diff to the `world_objects` row in place.
6. **Extract action** — `ExtractObjectEssence{blueprint_id, source_object_id, wizard_id}` is a wrapper-level operation: the dispatcher reads the source `world_objects` row, populates a `CreateObjectBlueprint` command with the wholesale-copied payload, and dispatches to a fresh `ObjectBlueprint` aggregate (slug supplied by the wizard at commit time, default-derived from the source object's name per FR-007b). The source object is **not** touched by this operation — extraction is a one-way distillation.
7. **Wizard authoring-mode state** — a per-LiveView-mount `:authoring_mode` assign (`:world` or `:blueprints`), NOT persisted to DB. Mode transitions are LiveView events that side-effect a `WizardEnteredTrance{wizard_id, room_id}` or `WizardExitedTrance{wizard_id, room_id}` event published on the existing `room:<room_id>` PubSub topic by a new `WizardTrance` module — no aggregate, just a transient broadcast (consistent with how examination/whisper push transient log entries today).
8. **LLM intent resolver extension** — the existing `IntentResolver` from feature 005 gains a wizard-mode tool set: `manifest_object_freeform`, `spawn_object_from_blueprint`, `draft_object_blueprint`. The `current_context` shape is extended with `authoring_mode`, `focused_object_id`, `focused_blueprint_id` (FR-023). In `:blueprints` mode the resolver refuses tools that need a `room_id` (FR-024). No edit verbs anywhere in the tool set (FR-025).
9. **Wizard LiveView surface** — a new `WizardLive` LiveView (or, more likely, a new mode within the existing `GameLive` — see Phase 0 research) that renders spec 001's wizard chrome wired to real data. The kind picker from spec 001 is removed; replaced by the prompt textarea (creation) + Interpreted Data form card (editing). The footer is two buttons (Discard / Commit) per Q3 clarification.
10. **Spec 001 mockup adaptations** captured in this spec's Clarifications + Assumptions sections: kind picker removed, footer simplified to two buttons, "Save as draft" deferred, Item label preserved as user-facing copy over the codebase's Object entity.

This is a substrate milestone. The headline UX (wizards manifesting items into the world) is in scope; advanced wizardry (NPCs, behaviors, room digging, region permissions, blueprint deletion) is not — see Assumptions for the full deferred list. NPC blueprints follow in milestone 2 and will also fold spec 008's existing event names and lineage FK into this milestone's simpler pattern.

## Technical Context

**Language/Version**: Elixir 1.15+ on OTP 26+ (existing project baseline; consistent with feature 013).

**Primary Dependencies (existing, reused — no new dependencies)**:
- `phoenix ~> 1.8`, `phoenix_live_view ~> 1.1.0`, `phoenix_pubsub` — wizard view extends the existing `GameLive`/`game_components.ex` surface from spec 001; trance entries broadcast on the existing `room:<room_id>` topic via `UIEventBroadcaster`.
- `commanded ~> 1.4` + `commanded_eventstore_adapter ~> 1.4` — used for the new `ObjectBlueprint` aggregate and for the new commands that mutate `Room` aggregates. No changes to Commanded routing infrastructure beyond a new aggregate identification entry.
- `ecto_sql ~> 3.11` + `postgrex` — schema migrations for `players` (adds `is_wizard`), `object_blueprints` (new table).
- `jason ~> 1.4` — already used for event payload serialization.

**Reused project infrastructure**:
- `AgenticRealms.World.Router` (`world/router.ex`) — extended with `identify(ObjectBlueprint, by: :blueprint_id, prefix: "object-blueprint-")` and a new dispatch entry for `[CreateObjectBlueprint, EditObjectBlueprint, ExtractObjectEssenceInto]`. Adds `SpawnObjectFromBlueprint`, `SpawnObjectFreeform`, `EditObject` to the existing `Room` aggregate's dispatch list (the `Room` aggregate already owns object placement via the spec 013 / spec 007 lineage).
- `AgenticRealms.World.Commands` (`world/commands.ex`) — adds wrappers `create_object_blueprint/2`, `edit_object_blueprint/3`, `spawn_object_from_blueprint/3`, `spawn_object_freeform/3`, `edit_object/3`, `extract_object_essence/3`. Each wrapper performs the wizard-authorization check (read `is_wizard` from the read model; refuse with `{:error, :not_a_wizard}` if false), any read-model pre-validation (e.g., blueprint slug uniqueness for create; current revision capture for edit; source-object existence for extract), then dispatches.
- `AgenticRealms.World.IntentResolver` (`world/intent_resolver.ex`) — extended with a per-mode tool set selection. In `:world` mode for a wizard the tool set is `{manifest_object_freeform, spawn_object_from_blueprint}` plus the existing player-side tools. In `:blueprints` mode the tool set is `{draft_object_blueprint}` only — no spatial tools. The `current_context` payload (`world/intent_resolver/context_snapshot.ex`) gains `authoring_mode`, `focused_object_id`, `focused_blueprint_id`.
- `AgenticRealms.UIEventBroadcaster` — extended with handlers for the new events that broadcast: `ObjectSpawned` → `RoomObjectArrived` (consistent with the existing `RoomNPCArrived` pattern from spec 007); `ObjectEdited` → `RoomObjectEdited` on `room:<room_id>` so co-present players see the updated examine output; `ObjectBlueprintCreated` / `ObjectBlueprintEdited` → `WizardBlueprintRegistryChanged` on a new `blueprints` global topic so any wizard with the registry open gets live updates. The new `WizardEnteredTrance` / `WizardExitedTrance` transient events broadcast directly on `room:<room_id>` as system log entries.
- `AgenticRealmsWeb.GameLive` — extended with a per-mount `:authoring_mode` assign and event handlers for `toggle_authoring_mode`, `commit_blueprint_draft`, `discard_blueprint_draft`, `commit_object_edit`, `extract_essence`, `spawn_here`. Each handler authorizes (`is_wizard`), reads relevant context (focused entity, current room), dispatches via the appropriate `Commands` wrapper.
- `AgenticRealmsWeb.GameComponents` (`game_components.ex`) — the existing wizard mockup chrome from spec 001 is wired to real data. The kind picker is removed; the prompt textarea routes through the LLM intent resolver; the Interpreted Data card binds to a `:focused_blueprint` or `:focused_object` assign and is editable directly. New chrome for the mode toggle (button), the registry tab (`blueprints_registry/1`), and the per-focused-thing footer (two buttons: Discard / Commit).
- `AgenticRealms.Accounts` (`accounts.ex`) — extended with `promote_to_wizard/1` (plain Ecto update, idempotent). The accompanying `Accounts.Player` schema gains an `is_wizard` field.

**Storage**:
- **Extended `players`** (`accounts/player.ex`): adds `is_wizard` (boolean, NOT NULL, DEFAULT `false`). The migration backfills `false` for all existing rows; existing accounts continue to function unchanged. No new indexes — `is_wizard` is read in conjunction with the player's primary key for every authz check, so the implicit PK index is sufficient.
- **New table `object_blueprints`**: `id` (string PK, NOT NULL, matches `^[a-z][a-z0-9_]*$`, length 1–64 — the slug per FR-007a; UUIDs explicitly disallowed by check constraint), `kind` (string NOT NULL, fixed value `"object"` in this milestone — check constraint enforces, leaving room for milestone 2 to add `"npc"`), `name` (string NOT NULL), `short_description` (string NOT NULL), `long_description` (text NOT NULL), `fixed` (boolean NOT NULL DEFAULT `false`), `revision` (integer NOT NULL DEFAULT 1, CHECK `> 0`), `created_at` / `updated_at` (utc_datetime NOT NULL). No `created_by_wizard_id` (per FR-006a and Q1 clarification). No `blueprint_id` self-reference. The blueprint id IS the slug — no separate UUID surrogate. Index on `kind` (cheap, supports milestone 2's mixed-kind queries).
- **`world_objects` unchanged**. The existing schema from features 003/006/013 covers everything milestone 1 needs. No `blueprint_id` column is added (per FR-013). The existing fields (`name`, `short_description`, `long_description`, `fixed`, `behaviors`, `room_id`, `player_id`, `quest_*`) cover both blueprint-spawn and freeform-create paths; `behaviors` stays `[]` (out of scope), quest fields stay NULL.
- **Persistent state is read-replay-safe**. `object_blueprints` is rebuildable from `ObjectBlueprintCreated` + `ObjectBlueprintEdited` events. `world_objects` rows added by this milestone are rebuildable from `ObjectSpawned` + `ObjectEdited` events. Spec 008's existing NPC tables are untouched.
- **No new volatile state**. The wizard's `:authoring_mode` is per-LiveView mount only (in `socket.assigns`). The trance transient events are not persisted to any table — they live in the event log briefly for projection by `UIEventBroadcaster`, the broadcaster fires the `room:<room_id>` log entry, and that's it.

**Testing**:
- `ExUnit` (existing) — unit + projector + LiveView.
- **Aggregate unit tests** (`test/agentic_realms/world/object_blueprint_test.exs`, new):
   - `ObjectBlueprint.execute/2` + `apply/2`: `CreateObjectBlueprint` from `id: nil` state emits `ObjectBlueprintCreated` with `revision: 1`; from initialized state returns `{:error, :already_exists}`. `EditObjectBlueprint` with matching known revision emits `ObjectBlueprintEdited` with `revision: N+1` only when at least one content field changed; with non-matching known revision returns `{:error, :stale_revision, current_revision: <int>}`; with matching revision and no field changes returns `:ok` (no event, no revision bump per FR-008). Mid-stream replay reconstructs state correctly.
- **Aggregate diff unit tests** (`test/agentic_realms/world/room_object_extensions_test.exs`, extends existing Room aggregate tests):
   - `SpawnObjectFromBlueprint` emits `ObjectSpawned` with the denormalized payload supplied by the dispatcher (the aggregate does NOT re-read the blueprint — by FR-013 it doesn't have a reference to read).
   - `SpawnObjectFreeform` emits the same shape of `ObjectSpawned`. The two are observationally identical at the aggregate boundary.
   - `EditObject` emits `ObjectEdited` with the diff fields only; no-op edits return `:ok` with no event.
- **Authorization unit tests** (`test/agentic_realms/world/commands/wizard_authz_test.exs`, new):
   - Each `Commands` wrapper that mutates Blueprint or Object state refuses with `{:error, :not_a_wizard}` when the actor's `is_wizard` is `false`, without dispatching.
   - `Accounts.promote_to_wizard/1` flips the flag and is idempotent on a second call.
   - `Accounts.promote_to_wizard/1` returns `{:error, :not_found}` for an unknown player id.
- **Projector tests** (`test/agentic_realms/world/projections/object_blueprint_projector_test.exs`, new):
   - `ObjectBlueprintCreated` → inserts a `object_blueprints` row with `revision: 1` and the event payload's fields. Idempotent replay (`on_conflict: :nothing`).
   - `ObjectBlueprintEdited` → updates the existing row's fields and bumps `revision`. Idempotent replay using `revision` as a guard.
- **Extended projector tests** (`test/agentic_realms/world/projections/world_projector_test.exs`, existing):
   - `ObjectSpawned` → inserts `world_objects` row matching the payload.
   - `ObjectEdited` → updates `world_objects` row in place.
   - Both replay idempotently.
- **Intent resolver tests** (`test/agentic_realms/world/intent_resolver/wizard_tools_test.exs`, new):
   - In `:world` mode for a wizard, a prompt describing an object dispatches `SpawnObjectFreeform` (or, when an entity name resolves to a known blueprint, `SpawnObjectFromBlueprint`).
   - In `:blueprints` mode, the same spatial prompt is refused with a hint that spatial actions aren't available in trance (FR-024).
   - Edit-phrased prompts in either mode produce a non-actionable response (FR-025).
- **LiveView integration tests** (`test/agentic_realms_web/live/wizard_live_test.exs`, new):
   - Promote a player via `Accounts.promote_to_wizard/1`, sign in, see the top-bar Wizard switch.
   - Toggle to Wizard mode, then to Sanctum; verify a co-present player's log gains the `enters a trance.` entry within 500ms.
   - Submit a blueprint prompt, see Interpreted Data populate (mocked LLM in this test — no real API calls), click Commit, see the registry update.
   - Toggle back to World; verify the `appears to come out of a trance.` entry. Click Spawn here on the registry row; verify the Object appears in the co-present player's room view.
   - Click an existing Object, edit a field via the form, click Commit; verify the persisted row updates and a co-present player's next examination shows the new value.
   - Click Extract essence on an existing freeform Object; verify the wizard flips to Sanctum, the Interpreted Data card pre-populates with the source object's fields, the source object's row is unchanged after the wizard clicks Commit.
- **Authorization integration tests** (`test/agentic_realms_web/live/wizard_authz_test.exs`, new):
   - A non-wizard signing in sees NO top-bar Wizard switch.
   - A non-wizard attempting to push a `toggle_authoring_mode` event over the LiveView socket (crafted manually) receives a refusal and no state change occurs.
   - A non-wizard whose session predates promotion sees the Wizard switch appear on next mount after `promote_to_wizard/1` is invoked.
- **Concurrent-edit conflict test** (`test/agentic_realms_web/live/blueprint_optimistic_lock_test.exs`, new): two LiveView clients both focus the same Blueprint, both edit, both Commit. The first commit succeeds (revision N → N+1); the second commit receives the stale-revision error and surfaces the latest version in the form.

**Target Platform**: Linux server BEAM cluster (production); macOS BEAM single-node (dev). Identical to features 012, 013.

**Project Type**: Phoenix LiveView web application.

**Performance Goals**:
- Trance entry/exit broadcast end-to-end (LiveView event → co-present player's DOM update): ≤ 500 ms p95 per SC-003. Achieved trivially via the existing `room:<room_id>` PubSub path used by feature 003's live-witness model.
- Object spawn end-to-end (wizard click → co-present player's narrative log): ≤ 2 seconds p95 per SC-002.
- Blueprint authoring end-to-end (toggle → Commit → registry update visible): ≤ 90 seconds p95 per SC-001, dominated by LLM extraction latency.
- Optimistic-lock conflict detection latency: identical to a normal Blueprint edit. The lock check is a single integer compare inside the aggregate execute/2; cost is negligible.
- Registry list query: `SELECT id, name, revision, short_description FROM object_blueprints ORDER BY name LIMIT 200` against the implicit PK index. Sub-millisecond at any realistic milestone-1 scale (≤ 10⁴ blueprints).

**Constraints**:
- **No new dependencies.** All work within the existing Elixir/Phoenix/Commanded/Ecto stack.
- **`is_wizard` is plain Ecto, not event-sourced.** Consistent with the existing `Accounts` module style (registration, password change, preferences are all plain Ecto). This is a deliberate divergence from the world's event-sourcing pattern, documented in research.md.
- **Event log is destroyable in this phase** — per the `event-log-destroyable-phase` project memory. New aggregates and events ship without any cross-milestone event-stream migration. Existing spec 008 NPC events stay as-is in milestone 1; milestone 2 renames them.
- **No `blueprint_id` on Object rows or Object events.** This is a load-bearing invariant of milestone 1's design (FR-013, FR-029). The `world_objects` schema does NOT gain a `blueprint_id` column; the `ObjectSpawned` event does NOT carry `blueprint_id`. Enforced at the schema level (no column) and at the event schema level (no field).
- **Optimistic lock check lives in the aggregate.** The `EditObjectBlueprint` command MUST be refused at the `ObjectBlueprint` aggregate's `execute/2` boundary, not in the projector or in the LiveView. This is what allows concurrent commits from two LiveView clients to race correctly: the second command reaches the aggregate, sees a different `revision`, and is refused before any event is appended.
- **Wizard authorization is checked twice:** once at the LiveView event handler entry (cheap UX gate; refuses early), and once at the `Commands` wrapper entry just before `Commanded.Application.dispatch/2`. Both checks read `is_wizard` from the `players` read model. A non-wizard cannot reach the aggregate even via a crafted client event.

**Scale/Scope**:
- Expected wizard count in early phases: 1–5 (small dev/early-tester pool).
- Expected Object Blueprints per wizard: 10–100 over the project's substrate-development phase. Total milestone-1 blueprint count: ≤ 10⁴ comfortably; registry stays flat-list and unpaginated.
- Expected Objects in the world: roughly the existing seed quantity (≤ 10²) plus whatever wizards manifest. Milestone-1 ceiling: ≤ 10⁴ objects without redesign.
- Expected concurrent-edit conflicts: extremely rare (multiple wizards co-editing the same Blueprint in the same minute). The optimistic-lock check is paying premium for a rare event, but the cost is essentially zero (one integer compare per commit) so the conservative choice is justified.

## Constitution Check

**Constitution file**: `.specify/memory/constitution.md` remains at template defaults (no concrete ratified principles). There are no enumerated gates to evaluate. PASS by default. Re-checked after Phase 1 design: no new gate considerations introduced.

## Project Structure

### Documentation (this feature)

```text
specs/014-item-blueprints/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── commands.md
│   ├── events.md
│   ├── intent_tools.md
│   └── ui_events.md
└── tasks.md             # Phase 2 output (/speckit-tasks command)
```

### Source Code (repository root)

```text
lib/agenticrealms/
├── accounts.ex                                   # +promote_to_wizard/1
├── accounts/
│   └── player.ex                                 # +is_wizard field
├── world/
│   ├── application.ex                            # +ObjectBlueprintProjector child
│   ├── commands.ex                               # +6 wrapper functions (authz + dispatch)
│   ├── commands/
│   │   ├── create_object_blueprint.ex            # NEW
│   │   ├── edit_object_blueprint.ex              # NEW
│   │   ├── spawn_object_from_blueprint.ex        # NEW
│   │   ├── spawn_object_freeform.ex              # NEW
│   │   ├── edit_object.ex                        # NEW
│   │   └── extract_object_essence.ex             # NEW (synthetic — calls Create with copied payload)
│   ├── events/
│   │   ├── object_blueprint_created.ex           # NEW
│   │   ├── object_blueprint_edited.ex            # NEW
│   │   ├── object_spawned.ex                     # NEW
│   │   ├── object_edited.ex                      # NEW
│   │   ├── wizard_entered_trance.ex              # NEW (transient)
│   │   └── wizard_exited_trance.ex               # NEW (transient)
│   ├── intent_resolver.ex                        # +wizard-mode tool selection
│   ├── intent_resolver/
│   │   └── context_snapshot.ex                   # +authoring_mode, +focused_*_id fields
│   ├── object_blueprint.ex                       # NEW aggregate (Commanded)
│   ├── projections/
│   │   ├── object_blueprint_projector.ex         # NEW
│   │   └── world_projector.ex                    # +ObjectSpawned, +ObjectEdited handlers
│   ├── room.ex                                   # +SpawnObjectFromBlueprint, +SpawnObjectFreeform, +EditObject command handlers
│   ├── router.ex                                 # +ObjectBlueprint aggregate ident + dispatch
│   ├── schemas/
│   │   └── object_blueprint.ex                   # NEW Ecto schema
│   ├── ui_event_broadcaster.ex                   # +handlers for the 6 new events
│   └── wizard_trance.ex                          # NEW (transient broadcast helper)
└── agentic_realms_web/
    ├── live/
    │   └── game_live.ex                          # +:authoring_mode assign, +6 event handlers, +authz checks
    ├── components/
    │   └── game_components.ex                    # spec 001 wizard chrome → wired to real data; +mode toggle, +blueprints_registry, simplified footer
    └── topics.ex                                  # +blueprints topic helper (matches existing room:/player: pattern)

priv/repo/migrations/
├── 2026XXXXXXXXXX_add_is_wizard_to_players.exs   # NEW
└── 2026XXXXXXXXXX_create_object_blueprints.exs   # NEW

test/agentic_realms/
├── accounts_test.exs                              # +promote_to_wizard cases
├── world/
│   ├── object_blueprint_test.exs                  # NEW aggregate tests
│   ├── room_test.exs                              # +object spawn/edit cases
│   ├── intent_resolver/wizard_tools_test.exs      # NEW
│   ├── commands/wizard_authz_test.exs             # NEW
│   └── projections/object_blueprint_projector_test.exs # NEW
└── agentic_realms_web/
    └── live/
        ├── wizard_live_test.exs                    # NEW end-to-end
        ├── wizard_authz_test.exs                   # NEW
        └── blueprint_optimistic_lock_test.exs      # NEW
```

**Structure Decision**: The feature lives entirely within the existing single-project Phoenix layout. No new top-level directories. The new `world/object_blueprint.ex` aggregate sits alongside the existing `world/room.ex`, `world/player.ex`, `world/npc_blueprint.ex` aggregates. The new projector sits alongside the existing `world/projections/world_projector.ex`. Wizard UI lives inside the existing `GameLive` LiveView with a per-mount `:authoring_mode` assign — a separate `WizardLive` was considered (see research.md) but rejected for the simpler single-LiveView approach since the wizard view shares most of its chrome with the player view (topbar, room context, presence).

## Complexity Tracking

> No constitution violations — constitution is at template defaults.

| Decision | Rationale | Simpler Alternative Rejected Because |
|----------|-----------|-------------------------------------|
| Optimistic lock at aggregate, not at projector or LiveView | Two-LiveView race correctly serialized at the event store boundary | Projector-level check leaves a window where two LiveViews both see "no conflict" before the projector applies either |
| Single `GameLive` with `:authoring_mode` assign | Wizard chrome shares ~80% of its surface (topbar, room context, presence) with player chrome | Separate `WizardLive` would duplicate the topbar / room-context / presence wiring |
| `is_wizard` as plain Ecto, not event-sourced | Matches existing `Accounts` module style; promotion is rare and admin-driven, not a domain event | Adding an `AccountAggregate` for one boolean introduces a new aggregate context for marginal audit value |
| Two-step authorization (LiveView entry + Commands wrapper entry) | LiveView check is the cheap UX gate; Commands wrapper is the security boundary | LiveView-only check is bypassable via crafted socket messages; Commands-only check produces a confusing UX (refusal after submit instead of disabling the surface) |
