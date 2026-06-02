# Phase 0 Research: Wizard-Created Object Blueprints (Milestone 1)

This document resolves the planning-level decisions implied by the spec but not pinned by clarifications. Each entry follows: **Decision → Rationale → Alternatives considered**.

## R1. Wizard authorization storage: plain Ecto vs event-sourced

**Decision**: `Accounts.Player.is_wizard` is a plain boolean column on the `players` table, mutated via `Accounts.promote_to_wizard/1` (an Ecto update). Promotion is **not** event-sourced; there is no `PromoteToWizard` Commanded command and no `PlayerPromotedToWizard` event.

**Rationale**:
- The existing `Accounts` module is non-event-sourced — registration, password change, preferences update are all plain Ecto. Introducing a single event-sourced operation in an otherwise plain context would split the module's mental model.
- The audit value of an event log entry for "player X was promoted on date Y" is low in this phase. The destroyable-event-log phase (see project memory `event-log-destroyable-phase`) means stream-level audit guarantees are not load-bearing.
- The world-side authorization check just reads `is_wizard` from the `players` read model. There is no need for the world aggregates to subscribe to a wizard-status stream; the synchronous read is correct.
- The user's wording "function that issues a PromoteToWizard command" was interpreted as colloquial — "command" as in "named operation," not as in `Commanded.Command`. This is consistent with their explicit "no UI needed; invoke from `iex`" framing.

**Alternatives considered**:
- *Event-sourced via a new `Accounts.PlayerAccount` aggregate*. Rejected for the cost-vs-value reasons above. If a future milestone introduces other event-sourced account operations (role revocations, two-factor toggles, etc.), promote-to-wizard can be folded in alongside them with no read-model schema change.
- *Implicit wizard status via `is_admin` or similar pre-existing field*. There is no such field today; introducing `is_admin` to repurpose for wizard-mode is naming-poor. `is_wizard` is the precise concept.

## R2. Wizard LiveView placement: extend `GameLive` vs new `WizardLive`

**Decision**: Extend the existing `AgenticRealmsWeb.GameLive` with a per-mount `:authoring_mode` assign and wizard-conditional chrome. Do NOT create a separate `WizardLive`.

**Rationale**:
- The wizard view shares the topbar (branding, user info), the room context (current room banner, presence list), the map, and the player presence wiring with the player view. A separate LiveView would duplicate all of that or extract it into yet another layer of shared components — net cost is higher than the conditional chrome.
- Spec 001's mockup conceptually treats Player and Wizard as a mode switch within a single shell. The single-LiveView implementation matches that mental model directly.
- The `:authoring_mode` assign branches downstream rendering decisions cleanly (sanctum chrome vs world chrome, blueprints registry tab visibility, footer button set, prompt placeholder text, etc.).
- The mode toggle is a single LiveView event handler that pushes a transient `WizardEnteredTrance` / `WizardExitedTrance` event via the existing PubSub topic. No URL change, no remount, no session loss.

**Alternatives considered**:
- *Separate `AgenticRealmsWeb.WizardLive` at `/wizard`*. Rejected as above. The URL split would also create a UX wart where wizards have to navigate to a different route to enter trance — but trance is conceptually still "the wizard, in their current room, mentally elsewhere." A route boundary doesn't match.
- *Modal/dialog for wizard mode*. Rejected because trance is not a transient interruption; wizards spend extended time authoring. A modal would obstruct the rest of the chrome unnecessarily.

## R3. Trance broadcast mechanism: aggregate-emitted event vs transient broadcast

**Decision**: Trance entry/exit emits `WizardEnteredTrance{wizard_id, room_id}` and `WizardExitedTrance{wizard_id, room_id}` events. These are persisted to the event store like any other event (so projections and the `UIEventBroadcaster` can react), but no **aggregate state** is mutated — the wizard's `authoring_mode` lives only in the LiveView socket assigns, not in any persistent aggregate. A small `AgenticRealms.World.WizardTrance` helper dispatches these events through `Commanded.Application` without owning aggregate state, similar to how transient log events are emitted elsewhere in the codebase.

**Rationale**:
- The `UIEventBroadcaster` is the canonical surface for "tell the room about something that just happened." Plumbing trance entries through it gives co-present players' narrative logs the entries via the existing live-witness pipeline used by every other room-scoped notification.
- Putting trance state in an aggregate would mean introducing a `WizardSession` aggregate or attaching mode state to the existing `Player` aggregate. The first adds an aggregate for no persistent state (the wizard's mode resets on reconnect per FR-005). The second mixes UI session state with the in-world Player aggregate's concerns (current room, discovered rooms) — the abstractions don't fit.
- The event is needed because the read model has no idea what the wizard's LiveView socket is doing; only the LiveView itself knows when the toggle flipped. Emitting an event from the LiveView (via a small `WizardTrance.enter/2` helper) is the cleanest bridge from "LiveView-local state change" to "world-side broadcast."

**Alternatives considered**:
- *Pure PubSub broadcast, no event*. Rejected because the project's pattern for room-witness log entries goes through the event log; bypassing it would create a parallel notification path that doesn't replay and is harder to test.
- *Trance state on the `World.Player` aggregate, transitioning via `EnterTrance` / `ExitTrance` commands*. Rejected because the aggregate doesn't need to track this — there's no decision the aggregate makes based on trance state. The mode is purely a UI session concern.

## R4. Blueprint id scheme: slug-only

**Decision**: The Blueprint id IS the slug (e.g., `brass_bound_chest`). There is no UUID surrogate key. The slug is the primary key of `object_blueprints`, the aggregate identifier in Commanded, and the foreign-key shape that any future feature would point at.

**Rationale**:
- Spec 008's NPC Blueprints already use the same pattern (`garrick_the_innkeeper`, `orchard_keeper`). Object Blueprints follow suit for consistency.
- Human-typability is the headline property (per FR-007a and the late-arriving correction during clarification). UUID surrogates would defeat the wizard's ability to type the id in prompts and iex.
- The slug constraint (`^[a-z][a-z0-9_]*$`, length 1–64) ensures the id is always safe to use as a URL segment, a string literal in code, and an Elixir atom if ever needed.
- Globally-unique slugs are easy to enforce via a PK constraint. Collisions surface at commit time as `{:error, :slug_already_exists}` and are presented to the wizard in the form (FR-007b).

**Alternatives considered**:
- *UUID PK + slug as a unique secondary column*. Rejected as added complexity for zero benefit — every foreign-key reference would still use the slug for human-readability, leaving the UUID as dead surrogate weight.
- *Numeric serial like spec 008's per-blueprint `next_serial`*. Spec 008 uses the serial for *clones*, not for blueprints; blueprints in spec 008 are also slug-keyed. No precedent here.

## R5. Optimistic lock implementation site

**Decision**: The lock check lives in `ObjectBlueprint.execute/2` for the `EditObjectBlueprint` command. The command carries an `expected_revision` field. If `expected_revision != aggregate.revision`, the command returns `{:error, :stale_revision, current_revision: aggregate.revision}` and no event is emitted.

**Rationale**:
- The aggregate is the only writer to the event stream for this blueprint. Putting the check anywhere upstream (LiveView, Commands wrapper) means two concurrent edits can both pass the upstream check and both reach the aggregate, where only one can succeed — but by then events may have raced. The aggregate is the natural serialization point.
- The aggregate's `revision` is its in-process state and is replayed from the event stream on cold start, so the check is replay-correct without any extra plumbing.
- The error shape `{:error, :stale_revision, current_revision: N}` lets the LiveView surface the fresh state directly to the user without an extra read round-trip.

**Alternatives considered**:
- *Database-level `xmin` check or `WHERE revision = N` clause in the projector update*. Rejected because the projector is downstream of the aggregate; by the time the projector runs, the events have already been appended. Two concurrent winning aggregates would both produce events.
- *LiveView-side optimistic UI ("you may have stale data — reload before committing")*. Rejected because it relies on the LiveView to be honest; a crafted socket message bypasses it.

## R6. Spec 008 NPC events: rename now or defer to milestone 2

**Decision**: Defer. Milestone 1 leaves `NPCClonedFromBlueprint`, `npc_clones.blueprint_id`, the I-1 invariant, and the `synthetic_blueprint_id/3` helper exactly as feature 008 shipped. Milestone 2 — when wizard-authored NPCs land — renames `NPCClonedFromBlueprint` to `NPCSpawned`, drops the `blueprint_id` FK, drops the I-1 invariant, and removes the synthetic blueprint scaffolding.

**Rationale**:
- Scoping milestone 1 to objects keeps the migration surface small and the substrate spec lean.
- Renaming spec 008's events in milestone 1 would force milestone 1 to touch NPC code without any user-visible NPC feature shipping, which is gratuitous.
- The destroyable-event-log phase means deferring the rename costs nothing — when milestone 2 ships, the event log is wiped, the new events are emitted from clean projections, and the rename is invisible to users.

**Alternatives considered**:
- *Rename in milestone 1 to unify the substrate*. Rejected for the scope reasons above. Milestone 1's user value is "authoring objects." NPC churn would be invisible to the user and add risk to milestone 1's delivery window.
- *Rename in milestone 1 but leave the data model alone (only event-name rename)*. Rejected as half-measure — half the rationale for the rename is dropping the `blueprint_id` FK, and a name-only change doesn't deliver that.

## R7. LLM intent resolver: extend existing vs new resolver

**Decision**: Extend the existing `AgenticRealms.World.IntentResolver` (from feature 005) with mode-aware tool selection. When the actor is a wizard in `:world` mode, the tool set is `{<existing player tools>, manifest_object_freeform, spawn_object_from_blueprint}`. When the actor is a wizard in `:blueprints` mode, the tool set is `{draft_object_blueprint}` only — no spatial tools, no player tools. When the actor is not a wizard, the tool set is the existing player-only set unchanged. The `current_context` payload (existing `ContextSnapshot`) gains `authoring_mode`, `focused_object_id`, `focused_blueprint_id` fields.

**Rationale**:
- The existing resolver already handles natural-language prompt → tool routing for players. Building a parallel resolver for wizards would duplicate the LLM client wiring, the prompt-cache integration, the `refuse` escape hatch, and the request/response shapes.
- Mode-aware tool selection is a small addition to the existing tool registry. The resolver already routes per-actor; per-mode is the next axis of that same dispatch.
- The wizard's prompt context (`focused_*_id`) is a natural extension of the existing context snapshot. The resolver already passes context to tools at invocation time.

**Alternatives considered**:
- *New `WizardIntentResolver` module*. Rejected — duplicates infrastructure, complicates the "which resolver am I" decision tree.
- *Two resolvers wired in parallel and merged at the LiveView*. Rejected — over-engineered for the modest scope of the wizard tool surface.

## R8. Form-based editing: per-action commands vs generic update command

**Decision**: Two narrow commands cover all editing: `EditObjectBlueprint{blueprint_id, expected_revision, fields_changed}` and `EditObject{object_id, fields_changed}`. The `fields_changed` map is a sparse diff (only the fields the wizard actually changed). No `UpdateObjectField{object_id, field_name, new_value}` style of per-field command.

**Rationale**:
- A single commit (clicking the Commit button) is a single user-intent unit. Wrapping it in a single command keeps the audit trail aligned with what the wizard saw and did.
- Sparse diffs make optimistic-lock failures recoverable: when the second wizard's commit fails with `:stale_revision`, the LiveView can show "your changes were: {short_description, fixed}; the current revision has been updated by another wizard since you started — here it is, please re-apply." Granular commands would obscure this intent.
- The aggregate's `apply/2` for the event only writes the fields present in the diff, so partial commits are well-defined.

**Alternatives considered**:
- *Per-field commands*. Rejected for diff-clarity reasons. Also produces a lot of micro-events for what users perceive as one action.
- *Full-payload command (every field every time)*. Rejected because it makes the "what did the wizard actually change" question harder to answer at audit time and clutters the event log.

## R9. Registry update propagation to other wizards' open registries

**Decision**: When `ObjectBlueprintCreated` or `ObjectBlueprintEdited` is emitted, the `UIEventBroadcaster` broadcasts a `WizardBlueprintRegistryChanged{blueprint_id, revision, name, short_description}` UI event on a new `blueprints` global topic. Any wizard with the registry tab open subscribes to this topic and updates the row (or inserts a new one) in place. No full registry reload.

**Rationale**:
- Multi-wizard sessions are explicitly in scope (per Q1's "global ownership"). Registry staleness across sessions is a real UX problem the spec implies but doesn't pin.
- The `blueprints` topic is global, not room-scoped, because the registry has no spatial dimension. Subscribers are any wizard's LiveView with the registry tab open.
- The payload is just enough for the registry row — name, revision, short_description snippet. Wizards who open a Blueprint for editing get the full payload via a separate read.

**Alternatives considered**:
- *No live registry updates (wizards must reload to see other wizards' work)*. Rejected — produces silent staleness, violates the "collaborative authoring" tone of Q1's clarification.
- *Per-Blueprint subscription topics*. Rejected as more topics than needed for the modest registry volume.

## R10. Where the LLM extraction is hosted

**Decision**: Reuse the existing Anthropic-client + prompt-cache infrastructure from feature 005 (`AgenticRealms.World.IntentResolver` and its dependencies). The wizard's prompt is an additional invocation site for the same client, with a different system prompt (focused on object/blueprint extraction) and a different tool set.

**Rationale**:
- No new external integration. The existing `Claude` model + prompt-cache + async dispatch all carry over.
- The wizard prompts are richer (longer, more descriptive) than player commands, but the cost structure is the same per-call.
- Reusing the resolver means the `refuse` escape hatch (per feature 005's pattern) covers wizards too: if the LLM produces a non-tool response (e.g., a generic conversational answer to "tell me about Western Reach"), the resolver's existing refusal logic kicks in and the wizard sees an inline hint (per Story 3 Acc 3).

**Alternatives considered**:
- *Direct Anthropic SDK call in the LiveView*. Rejected as bypassing the resolver's central abstraction.
- *Background job for extraction*. Rejected — the wizard expects synchronous progressive reveal of fields; backgrounding would force a polling UX.

---

All NEEDS CLARIFICATION items from the Technical Context are resolved. No further research required before Phase 1 design.
