# Phase 0 Research: Entity Lifecycle — Clone & Move with Typed Containment

**Feature**: 016-entity-containment | **Date**: 2026-06-04 | **Spec**: [spec.md](./spec.md)

Resolves the design questions for the substrate before Phase 1. Each entry records the decision,
rationale, and rejected alternatives. The dominant constraints: **one uniform lifecycle for all
entities**, **full retrofit now** (objects, NPCs, take/drop), and **zero player-visible regression**.
The three spec clarifications (clone home, retrofit scope, wired containers) are already resolved in
the spec's Clarifications session; the research below realizes them concretely against the code.

## Starting-state facts (from code survey)

- **Two creation events** write `world_objects`: `ObjectPlacedInRoom` (seed + quest paths, carries
  behaviors + quest scope) and `ObjectSpawned` (wizard blueprint/freeform). Both are emitted by the
  **`Room` aggregate**, which tracks object presence in an `object_ids` MapSet.
- **take/drop** are `TakeObject`/`DropObject` on the **`Room` aggregate** → `ObjectTakenFromRoom` /
  `ObjectDroppedInRoom`. Location is `world_objects.room_id` / `world_objects.player_id` (both
  nullable) under an `exactly_one_location` **XOR** CHECK. **They DO broadcast witnesses**:
  `RoomObjectTaken` / `RoomObjectDropped` to the room.
- **NPC spawn** is `SpawnNPCClone` on the **`NPCBlueprint` aggregate** → `NPCClonedFromBlueprint`
  (carries `blueprint_id` + `serial` lineage); `npc_clones.room_id` is the only location (NPCs are
  room-only). Legacy `NPCSpawnedInRoom` (007) is replayed to synthesize blueprints.
- **Witness conventions today** (must be preserved — FR-014):
  | Action | Event | Witness broadcast |
  |---|---|---|
  | wizard spawn object | `ObjectSpawned` | `RoomObjectArrived` ("appears") |
  | seed/quest place object | `ObjectPlacedInRoom` | **none** (silent) |
  | take | `ObjectTakenFromRoom` | `RoomObjectTaken` |
  | drop | `ObjectDroppedInRoom` | `RoomObjectDropped` |
  | spawn NPC | `NPCClonedFromBlueprint` | `RoomNPCArrived` |
  | object/NPC departure | — | **none** (no generic departure exists; `RoomNPCLeft` defined but unemitted) |
- **`Player` is already an aggregate** (stream `player-<id>`) that owns `current_room_id` and emits
  `PlayerMoved`; the read side projects `player_state.current_room_id` with `:strong` consistency.
  This is the working precedent for "entity owns its own location."

## R1 — Entity-as-aggregate, modeled on the existing `Player` aggregate

**Decision**: Introduce one generic **`Entity`** aggregate (`lib/agenticrealms/world/entity.ex`),
stream-identified by `entity_id` with prefix `"entity-"`. It owns the entity's **existence**, its
**kind** (`:object | :npc`), and its **current container**. It handles `CloneEntity`, `MoveEntity`,
and `EditEntity`. `clone()` lives in a thin world-service wrapper (the `Commands` module) that mints
the entity stream; `clone_into` is the clone-then-move wrapper. This directly mirrors how the
`Player` aggregate already owns `current_room_id` via `MovePlayer`/`PlayerMoved`.

**Rationale**: Resolves FR-016/FR-018. The entity owning its own stream gives **FR-005 (serialized
moves)** and **FR-004 (exactly-one-container)** *for free* — a single aggregate stream serializes
all moves of that entity, and its container is single-valued by construction. The `Player`
aggregate proves the pattern works in this codebase. A "global world service" is just the wrapper
layer, not an aggregate (Commanded has no global aggregate); the region-aggregate-as-factory
alternative was rejected in the spec (bottleneck, couples entity moves to region state).

**Aggregate shape** (lean — fields live in the read model, not the aggregate):
```
defstruct id: nil, kind: nil, container: %ContainerRef{type: :void, id: nil}
```
The aggregate does **not** retain name/description/behaviors — those frozen fields flow through
`EntityCloned` to the projector. `EditEntity` validates existence and emits a sparse `EntityEdited`
diff; the read model applies it. (Keeping the aggregate lean avoids duplicating the read model and
keeps clone/move the focus; richer per-entity state can move onto the aggregate later if needed.)

**Alternatives rejected**:
- *Keep placement on the Room aggregate, add container columns only.* Rejected: leaves spawn/move
  bespoke per path, can't serialize a single entity's moves across containers, and keeps two spawn
  models (violates FR-012/SC-003).
- *Per-kind aggregates (`Object`, `NPC`).* Rejected: the move/containment logic is identical across
  kinds; a generic aggregate with a `kind` tag is DRY and is what makes the pathway uniform (FR-007).

## R2 — Typed container reference replaces the two-FK-XOR location model

**Decision**: Define a `ContainerRef` value `%{type: :void | :room | :player | :npc, id: term | nil}`
(void has `id: nil`). Replace `world_objects.room_id` + `player_id` + the `exactly_one_location` XOR
with **`container_type` (string, NOT NULL)** + **`container_id` (string, NULL only when
`container_type = 'void'`)**, plus a CHECK enforcing the type set and the void⇔null-id pairing.
Generalize `npc_clones` the same way (room-only in practice) and **drop its `blueprint_id` + `serial`
lineage** (FR-013). Events serialize `ContainerRef` as a map.

**Rationale**: The XOR model structurally cannot express the void or a third container type; a single
typed `(type, id)` reference can express all four (void/room/player/npc) and is the minimal change
that admits clone-into-void and NPC possession (FR-006/FR-012b). Generalizing `npc_clones` keeps the
projector uniform (one write shape for both kinds).

**Index/constraint migration**:
- Replace the room view / inventory filters: a room's contents = `WHERE container_type='room' AND
  container_id=$room`; a player's inventory = `WHERE container_type='player' AND container_id=$player`.
- Preserve feature-007 per-room name uniqueness via a **partial unique index** on
  `(container_id, lower(name)) WHERE container_type='room'`.

**Alternatives rejected**:
- *Keep `room_id`/`player_id`, add `npc_id` + relax XOR.* Rejected: doesn't express the void, and
  a widening set of nullable FKs is exactly the ad-hoc model we're replacing.
- *Polymorphic association table (`containments`).* Rejected: a typed column pair on the existing
  read rows is simpler, keeps the room/inventory queries single-table, and matches the "frozen row"
  model from specs 008/014.

## R3 — Witness policy keyed on `(kind, cause, from→to)` reproduces today's conventions exactly

**Decision**: `MoveEntity`/`EntityMoved` carry an optional **`cause`** tag
(`:spawned | :placed | :taken | :dropped | :relocated`, plus NPC `:spawned`). `EntityCloned` does
**not** broadcast (creation into the void is silent). The `UIEventBroadcaster` reacts to
`EntityMoved` and maps `(kind, cause, from_type→to_type)` to the **existing** UI structs so observed
behavior is unchanged:

| kind | cause | from→to | UI broadcast (unchanged) |
|---|---|---|---|
| object | `:spawned` | void→room | `RoomObjectArrived` |
| object | `:placed` | void→room | **none** (seed/quest silent; quest scoping preserved) |
| object | `:taken` | room→player | `RoomObjectTaken` |
| object | `:dropped` | player→room | `RoomObjectDropped` |
| object | `:relocated` | room→room | `RoomObjectArrived` + (new) departure — see note |
| npc | `:spawned` | void→room | `RoomNPCArrived` |
| any | any | →void | none today (consumption is silent; see R5) |

**Rationale**: From/to type alone cannot distinguish wizard-spawn (announces) from seed/quest-place
(silent) — both are void→room. A small `cause` tag carries that semantic so one uniform mechanism
reproduces the four distinct current behaviors and the silent paths, guaranteeing FR-014. `cause` is
metadata for the *announcement policy* only (like `from_direction` on player arrival); it does not
fork the move *mechanism*. A genuine room→room relocation has no current behavior to preserve, so it
gets the natural "departs / arrives" pair using the existing arrived struct plus a minimal departure
(introduced only as needed; NPCs don't relocate this milestone).

**Alternatives rejected**:
- *Infer announcement purely from from→to.* Rejected: cannot separate spawn vs place (both void→room).
- *Keep separate domain events per action for witnessing.* Rejected: that is the bespoke-event model
  we are removing; the witness is a UI-layer concern, not a domain-event-shape concern.

## R4 — A dedicated `EntityProjector` owns `world_objects` + `npc_clones`

**Decision**: Add `EntityProjector` (mirroring `ObjectBlueprintProjector`'s structure/supervision)
that handles `EntityCloned` (insert read row in the kind-appropriate table, container = void),
`EntityMoved` (update `container_type`/`container_id`; trigger the witness mapping is done by the
broadcaster, not here), and `EntityEdited` (apply sparse diff). Remove the object/NPC
placement/take/drop/clone handlers from `WorldProjector`, leaving it to own rooms, exits, regions,
and quest orchestration only. Both projectors are `:strong` and supervised in `application.ex`
`commanded_children/0` and `data_case.ex` `setup_commanded/0`.

**Rationale**: After the retrofit, all `world_objects`/`npc_clones` row writes are driven by Entity
events, so consolidating them in one projector is cohesive and keeps `WorldProjector` focused. A
separate projector matches the established `ObjectBlueprintProjector` precedent and isolates replay
concerns. (Folding the handlers into `WorldProjector` instead is a viable lower-churn alternative;
chosen the dedicated projector for separation — revisit in tasks if supervision overhead matters.)

**Idempotent replay**: `EntityCloned` insert uses `on_conflict: :nothing`; `EntityMoved`/`EntityEdited`
updates are last-writer by stream position (a move is absolute container assignment, so replay is
naturally idempotent).

## R5 — Seed, quest, and "destruction" retrofit; consumption = move-to-void

**Decision**: Rework all object/NPC creation call sites onto `clone_into`:
- **Seed** (`world/seed.ex`): object placement and NPC spawn call `clone_into(:object|:npc, fields,
  {:room, id})` instead of `PlaceObject` / `spawn_npc_clone`.
- **Quest item spawn** (projector-dispatched on `QuestAccepted`): dispatches `clone_into(:object,
  fields, {:room, id})` with `cause: :placed` and the quest scope carried in the cloned fields.
- **Quest reward** (`QuestRewardMinted`): `clone_into(:object, reward, {:player, player_id})`.
- **Quest item consumption / cleanup** (`QuestItemsConsumed` / `QuestItemsCleanedUp`): re-expressed
  as **`move(object, → void)`** — the object leaves every container and becomes invisible, which
  reproduces "removed from the world" without introducing a destroy primitive this milestone.

**Rationale**: One creation path (FR-012). Move-to-void gives a non-regressing "removal" using the
void the substrate already defines, and exercises the void state (US4) on a real path. A dedicated
`DestroyEntity`/`EntityDestroyed` (hard delete of the read row) is deferred — not needed for
non-regression and out of this milestone's lifecycle scope (clone/move).

**Alternatives rejected**:
- *Add `DestroyEntity` now.* Rejected: scope creep; move-to-void is sufficient and keeps the
  primitive set to clone/move.
- *Leave quest finalization on bespoke events.* Rejected: would retain a second model for object
  lifecycle (violates SC-003).

## R6 — Player movement stays on the `Player` aggregate (not folded into `Entity`)

**Decision**: Players continue to move via `MovePlayer`/`PlayerMoved` on the `Player` aggregate.
Players are **containers** (player inventory) and movers-between-rooms, but they are **not** generic
`Entity` instances (they have sessions, accounts, room-discovery, `:strong` mount-safety needs).

**Rationale**: Player movement already works cleanly and has bespoke needs (discovery, mount-time
strong consistency) that don't generalize to objects/NPCs. Unifying it would add risk for no benefit
this milestone. The `Player` aggregate is the *template* for `Entity`, not a thing to subsume.
(Possible future unification is noted as a non-goal.)

## R7 — Destination validation in the wrapper; name-collision pre-check preserved

**Decision**: Because an aggregate cannot read other aggregates/read-models, the **wrapper**
(`move_entity`/`clone_into`) validates: destination container exists (room/player/npc row present)
and, for room destinations, the destination has no name-colliding entity (feature-007 rule) — both
via read-model queries before dispatch. The `Entity` aggregate independently rejects a `MoveEntity`
whose stated `from` disagrees with its actual current container (authoritative current container,
FR-005) and a no-op move (to == current → `:ok`, no event, FR-009). Unknown container *type* is
rejected at the command/wrapper boundary (FR-010). The partial unique index is the backstop.

**Rationale**: Matches today's pre-dispatch validation in `Commands.take/drop` (resolve-then-dispatch)
and keeps the aggregate pure. Defense in depth: wrapper pre-check + aggregate invariant + DB index.

## R8 — NPC-inventory: defined in the model, dormant in the read/UI layer

**Decision**: `:npc` is a valid `ContainerRef.type` the `Entity` aggregate and wrapper accept and
validate (the NPC must exist), but **no** NPC-inventory read model, query, or witness is built; no
call site moves an object into an NPC this milestone. Room + player + void are fully wired.

**Rationale**: Realizes the FR-017 resolution (define-but-dormant). Proves the abstraction with two
live container types (room, player) + void while leaving NPC possession for the feature that needs it
(e.g., shopkeeper toolset in spec 015+) with zero model rework.

## Resolved unknowns summary

No `NEEDS CLARIFICATION` remain. Clone home (R1), container model (R2), witness preservation (R3),
projector ownership (R4), seed/quest/consumption retrofit (R5), player-movement boundary (R6),
validation/uniqueness (R7), and NPC-inventory dormancy (R8) are all settled and trace to the spec's
resolved clarifications and functional requirements.
