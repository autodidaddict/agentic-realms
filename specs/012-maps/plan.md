# Implementation Plan: Maps

**Branch**: `012-maps` | **Date**: 2026-05-26 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/012-maps/spec.md`

## Summary

This feature replaces the hardcoded mini-map mockup (`GameData.map_nodes`/`map_edges`) with a live, per-player, region-scoped map driven by real world state. It introduces **Region** as a first-class event-sourced entity, extends **Room** with `region_id` (FK), `map_visible` (bool), `elevation` (int), and optional `(map_x, map_y)`, and adds per-player **room discovery** tracking via a new `PlayerDiscoveredRoom` event + `player_discovered_rooms` read-model table. The 6-direction set is extended to 10 (adds the four diagonals: NE, NW, SE, SW); existing event/command/aggregate code that funnels through `World.Direction` picks up the new directions in one place.

A new `World.Direction.Geometry` module + an `Exits.Validator` enforce FR-024's strict-direction / flexible-distance rule at exit creation. A new `World.MapView` read model computes the per-player projection (region name, rooms-to-render, exit lines with kind + length, fog-of-war stubs, above/below presence, off-map state). The existing `mini_map/1` component is rewritten as an SVG-primary renderer that consumes `MapView` (no CSS-positioned `<div>`s anymore — SVG gives precise diagonal lines and clean icon overlay).

Migration is a **hard reset** per clarification Q3 — pre-existing rooms (and dependent exit/object/NPC-clone/player-current-room state) are purged; the seed re-authors a complete Blackmire region with explicit coordinates for every seeded room so the map demonstrates correctly on a fresh `mix ecto.reset`.

The user's explicit ask — *"the final rendered layout still needs to have a great UI/UX even with diagonals and up/down indicators"* — drives several specific design choices in [research.md](./research.md): fixed-cell-size grid (no auto-fit scaling), SVG-primary rendering, up/down chevrons placed in non-conflicting corners of each room glyph, fog-of-war as a gradient-faded stub plus a soft hatch cloud, cross-region exits styled with a dashed stroke + portal glyph, and the dir-pad expanded to a 3×3 compass pad plus a paired up/down column.

## Technical Context

**Language/Version**: Elixir 1.15+ on OTP 26+ (existing project baseline).

**Primary Dependencies (existing, reused)**:
- `phoenix ~> 1.8`, `phoenix_live_view ~> 1.1.0`, `phoenix_pubsub` — server-rendered SVG inside the LiveView template (no JS hook needed; LiveView diffs SVG attributes natively).
- `commanded ~> 1.4` + `commanded_eventstore_adapter ~> 1.4` — used for `Region` aggregate + `Room` event extension + `PlayerDiscoveredRoom` event.
- `ecto_sql ~> 3.11` + `postgrex` — schema migrations for `regions`, extended `world_rooms`, and `player_discovered_rooms`.
- `jason ~> 1.4` — already used for event serialization.

**No new dependencies.**

**Reused project infrastructure**:
- `AgenticRealms.World.Direction` — extended to add `:northeast`, `:northwest`, `:southeast`, `:southwest` to `@canonical`, with aliases (`"ne"`, `"northeast"`, etc.), opposites (`opposite(:northeast) → :southwest`), and `to_string/1` cases. Every existing call site (parser, aggregate, projector, UI broadcaster) picks up the new directions for free.
- `AgenticRealms.World.Commands.{CreateRoom, AddExit}` + matching events — extended with the new room fields (region_id, map_visible, elevation, map_x, map_y) and (for AddExit) integrated with the new direction set.
- `AgenticRealms.World.Projections.WorldProjector` — extended to project `RegionCreated`, extended `RoomCreated` (with new fields), and `PlayerDiscoveredRoom`.
- `AgenticRealms.World.Projections.PlayerStateProjector` — extended to emit `PlayerDiscoveredRoom` as a side effect of `PlayerSpawned` and `PlayerMoved` (the first time a player enters a given room).
- `AgenticRealmsWeb.GameComponents.mini_map/1` — REWRITTEN as an SVG-primary renderer over a `MapView` struct.
- `AgenticRealmsWeb.GameLive` — extended to compute and subscribe to `MapView` updates; existing `PlayerCurrentRoomChanged` UI event becomes the primary trigger for map re-render.

**Storage**:
- **New table `regions`**: `id` (binary_id PK), `name` (string NOT NULL UNIQUE), `inserted_at`, `updated_at`.
- **Extended `world_rooms`**: adds `region_id` (binary_id FK → `regions.id`, NOT NULL after migration), `map_visible` (bool NOT NULL DEFAULT true), `elevation` (integer NOT NULL DEFAULT 0), `map_x` (integer NULL), `map_y` (integer NULL). Partial unique index on `(region_id, elevation, map_x, map_y) WHERE map_x IS NOT NULL AND map_y IS NOT NULL` enforces FR-022a.
- **New table `player_discovered_rooms`**: `player_id` (bigint FK → `players.id`), `room_id` (binary_id FK → `world_rooms.id`), `discovered_at` (utc_datetime NOT NULL). PK `(player_id, room_id)`.
- **Persistent destructive migration**: as part of this feature's deployment, the migration script drops/truncates pre-existing `world_rooms`, `world_exits`, `world_objects`, `npc_clones`, `npc_blueprints`, and clears `current_room_id` on `player_state`. The replay-safe event-store reset is paired: `mix do event_store.drop, event_store.create, event_store.init, ecto.reset` re-seeds cleanly. Operators get a documented one-time reset path in [quickstart.md](./quickstart.md).
- **No volatile state** beyond Phoenix LiveView assigns.

**Testing**:
- `ExUnit` (existing) — unit + integration + LiveView render.
- **Unit**: `Direction` extended-canonical tests; `Direction.Geometry` per-direction coord-delta tests; `Exits.Validator` accept/reject matrix for FR-024; `MapView` computation tests against handcrafted region fixtures (single room, two-wing house, multi-floor, fog stub, hidden room, cross-region, off-map).
- **Projector replay**: `RegionCreated` + extended `RoomCreated` + `PlayerDiscoveredRoom` events all replay idempotently against an empty read model and a partially-populated one (`on_conflict: :nothing` pattern).
- **LiveView integration**: a single `@moduletag :integration` test exercises US1–US7 against a seeded `Blackmire` region with one multi-floor house, one fog-stubbed undiscovered neighbor, one hidden room with an east exit, and one cross-region exit to a stub `Hollowvale` region.
- **Snapshot**: a render-snapshot test of `mini_map/1` against three fixture `MapView` structs. Catches accidental visual regressions in the SVG output.

**Target Platform**: Linux server BEAM cluster (production); macOS BEAM single-node (dev). Tests on developer machines and CI. Phoenix LiveView frontend served to modern desktop browsers (Chromium, Firefox, Safari).

**Project Type**: Phoenix LiveView web application.

**Performance Goals**:
- `MapView.for_player/1` computation: O(D) where D is the number of rooms the player has discovered in the current region at the current elevation. Expected sub-millisecond for D ≤ 100.
- Map re-render on movement: server-side LiveView diff of the SVG block. Expected end-to-end latency (PlayerMoved event → browser DOM update) ≤ 1 second for SC-002/SC-005/SC-006.
- SVG render budget: cap viewable cells at a fixed window (default 11×11 cells centered on the current room) so render cost is bounded regardless of region size.

**Constraints**:
- **Information hiding (FR-005, FR-007, FR-008, FR-017)** — one-way exits, undiscovered destinations, and cross-region destinations MUST NOT leak through any rendered element, attribute, or DOM data attribute. The renderer is responsible for the suppression — `MapView` must not emit destination room ids for fog stubs, and SVG `<title>` tooltips must be elided or replaced with a generic label for fog stubs.
- **No raw elevation number (FR-012)** — neither the header nor any DOM attribute on the map element may carry the integer elevation. `MapView` exposes `has_above_rooms?`, `has_below_rooms?` booleans only; the renderer styles affordances from those.
- **Backward compatibility — none required.** Per FR-020b (Q3), pre-existing world state is purged.
- **Cluster correctness** — `MapView` is a pure read-model computation over Repo data; no GenServer state, no per-node caches. Works transparently on any node.

**Scale/Scope**:
- Expected typical region size: ≤ 200 rooms; ≤ 5 elevation slices; ≤ 1000 exits.
- Discovery rows: ≤ rooms-per-region × player count. Comfortable in Postgres at thousands of players × hundreds of rooms.
- Viewport window: 11×11 cells fixed. Discovered rooms outside the window are simply not rendered (no scrolling for MVP). Future work may add scroll/zoom.

## Constitution Check

**Constitution file**: `.specify/memory/constitution.md` remains at template defaults (no concrete ratified principles). There are no enumerated gates to evaluate. PASS by default.

## Project Structure

### Documentation (this feature)

```text
specs/012-maps/
├── plan.md                    # This file
├── research.md                # Phase 0 — rendering substrate, viewport sizing, icon placement, fog/cross-region visual treatments, dir-pad expansion
├── data-model.md              # Phase 1 — Region entity, extended Room, PlayerDiscoveredRoom, MapView read model
├── quickstart.md              # Phase 1 — manual smoke test (fresh reset → map renders → move → discover → cross-region)
├── contracts/                 # Phase 1
│   ├── region.md              #   Region aggregate, CreateRegion command, RegionCreated event
│   ├── room-extensions.md     #   CreateRoom / RoomCreated additions (region_id, map_visible, elevation, map_x, map_y); CreateExit validator integration
│   ├── direction.md           #   Direction module expansion: 10-direction canonical set + Direction.Geometry coord-delta module
│   ├── exit-validator.md      #   Exits.Validator (new) — FR-024 strict-direction / flexible-distance check
│   ├── discovery.md           #   PlayerDiscoveredRoom event, projection, emission rules
│   ├── map-view.md            #   World.MapView read model — struct shape, computation, off-map handling
│   └── mini-map-component.md  #   mini_map/1 LiveView component — props, SVG layout, accessibility
├── checklists/
│   └── requirements.md        # From /speckit.specify
└── tasks.md                   # Phase 2 — /speckit.tasks output (NOT created here)
```

### Source Code (repository root)

Single Phoenix project, layout consistent with features 005–011. New files marked `+`; modified `M`.

```text
agenticrealms/
├── lib/
│   ├── agenticrealms/
│   │   ├── application.ex                                   M  Add Region aggregate router entry to the World application; no new supervised processes for this feature.
│   │   └── world/
│   │       ├── direction.ex                                 M  Extend @canonical to include :northeast, :northwest, :southeast, :southwest. Add parse aliases (`"ne"`, `"sw"`, etc.). Extend opposite/1 (NE↔SW, NW↔SE). Extend to_string/1.
│   │       ├── direction/
│   │       │   └── geometry.ex                              + Pure module. delta(direction) → {:planar, {dx_sign, dy_sign}} | {:vertical, dz_sign}. consistent?(direction, source, target) → bool per FR-024. unit_vector(direction) → {dx, dy} for SVG line angle.
│   │       ├── region.ex                                    + Region aggregate. Handles `CreateRegion(region_id, name)` → emits `RegionCreated(region_id, name)`. apply/2 builds aggregate state for replay.
│   │       ├── commands/
│   │       │   ├── create_region.ex                         + New command.
│   │       │   ├── record_room_discovery.ex                 + New command. Dispatched to the existing World.Player aggregate to emit PlayerDiscoveredRoom (FR-013).
│   │       │   ├── create_room.ex                             M  Add fields: region_id (required), map_visible (default true), elevation (default 0), map_x (nullable), map_y (nullable). Validation moved to pre-dispatch wrapper in commands.ex.
│   │       │   └── add_exit.ex                                # (no struct change; validation added at dispatch layer — see commands.ex below)
│   │       ├── events/
│   │       │   ├── region_created.ex                        + New event.
│   │       │   ├── room_created.ex                            M  Add fields: region_id, map_visible, elevation, map_x, map_y. Defaults preserve forward-compat for re-replayed events emitted in this feature; historical pre-012 events DO NOT EXIST AFTER PURGE (per FR-020b), so no backward-compat shim is required.
│   │       │   └── player_discovered_room.ex                + New event. Emitted by PlayerStateProjector as a side dispatch on PlayerSpawned + PlayerMoved (first-entry-only check via read model).
│   │       ├── exits/
│   │       │   └── validator.ex                             + New module. Given an AddExit command + the source/target rooms (from read model), validates direction consistency per FR-024. Used by the pre-dispatch wrapper in commands.ex.
│   │       ├── room.ex                                        M  Extend execute/2 + apply/2 for the new CreateRoom fields. Aggregate's exits map continues to key on direction atom; new direction atoms (NE/NW/SE/SW) flow through unchanged.
│   │       ├── player.ex                                      M  Add `discovered_room_ids: MapSet.new()` to defstruct. Add execute/2 clause for RecordRoomDiscovery (emits PlayerDiscoveredRoom only when room is not yet in the MapSet — idempotency lives here, NOT in the projector). Add apply/2 clause for PlayerDiscoveredRoom. Register RecordRoomDiscovery in the router's dispatch list for World.Player.
│   │       ├── commands.ex                                    M  add_exit/3 wrapper now invokes Exits.Validator before dispatching. create_region/2 (new). create_room/* extended with the new fields. record_room_discovery/2 (new) — strong-consistency dispatch wrapper.
│   │       ├── projections/
│   │       │   ├── world_projector.ex                         M  Handle RegionCreated → insert into regions. Update RoomCreated handler to include the new fields. Add a handle clause for PlayerDiscoveredRoom that inserts the row with on_conflict: :nothing.
│   │       │   └── player_state_projector.ex                  M  In handle PlayerSpawned/PlayerMoved, after the existing current_room_id update, unconditionally dispatch `RecordRoomDiscovery(player_id, target_room_id)` against the existing `World.Player` aggregate. The aggregate's `discovered_room_ids` MapSet gates whether `PlayerDiscoveredRoom` is emitted. The projector NEVER inserts into `player_discovered_rooms` directly — that is forbidden by the project's event-sourcing invariant. See contracts/discovery.md.
│   │       ├── map_view.ex                                  + New module. Reads MapView from the player's perspective; pure DB query + struct assembly. See contracts/map-view.md.
│   │       ├── queries.ex                                     M  Add discovered_room_ids_for/1, list_rooms_in_region_at_elevation/3, list_exits_for_rooms/1, has_discovered_rooms_above?/3, has_discovered_rooms_below?/3 — all consumed by MapView. Promote any private helpers as needed.
│   │       ├── schemas/
│   │       │   ├── region.ex                                + New Ecto schema. Mirrors the regions table.
│   │       │   ├── room.ex                                    M  Add fields: region_id, map_visible, elevation, map_x, map_y. belongs_to :region.
│   │       │   ├── exit.ex                                    # (no changes)
│   │       │   └── player_discovered_room.ex                + New Ecto schema. Mirrors the player_discovered_rooms table.
│   │       └── seed.ex                                        M  Major rewrite. Creates Blackmire region first. Then re-authors the Stone Atrium / North Corridor / Dusty Library WITH explicit (region_id=Blackmire, elevation=0, map_x/map_y — see quickstart.md for the actual layout). Adds a second floor over the Stone Atrium (Up exit from atrium to a new "Atrium Loft" at elevation=1) to demonstrate the down icon and elevation filtering. Adds a stub `Hollowvale` region with one room and a cross-region exit from somewhere in Blackmire to demonstrate US6. Adds one map-hidden room with an exit from a visible room to demonstrate US5.
│   ├── agenticrealms_web/
│   │   ├── components/
│   │   │   └── game_components.ex                             M  mini_map/1 REWRITTEN as SVG-primary renderer over a MapView struct. dir_pad/1 helper (currently inline) extracted and EXPANDED to a 3×3 compass pad + paired Up/Down column. Above/Below affordances rendered in the map header next to the region name.
│   │   └── live/
│   │       └── game_live.ex                                   M  Compute initial MapView in mount/3. On PlayerCurrentRoomChanged (and on movement to a different region), recompute MapView and re-assign. Stop calling GameData.map_nodes/map_edges.
│   └── game_data.ex                                           M  DELETE map_nodes/0 and map_edges/0 (no longer used). DELETE any other map-mock references.
├── priv/
│   └── repo/
│       └── migrations/
│           ├── <ts1>_reset_world_for_maps.exs              + Destructive migration: TRUNCATE world_rooms, world_exits, world_objects, npc_clones, npc_blueprints CASCADE; nullify player_state.current_room_id. Documented in quickstart.md as a one-time hard reset (paired with `mix event_store.reset`).
│           ├── <ts2>_create_regions.exs                    + Creates regions table.
│           ├── <ts3>_extend_world_rooms_with_map_fields.exs + Adds region_id, map_visible, elevation, map_x, map_y to world_rooms; creates the partial unique index on (region_id, elevation, map_x, map_y) WHERE map_x IS NOT NULL AND map_y IS NOT NULL. region_id becomes NOT NULL (paired with the reset migration so all surviving rows already have it — but rows have been truncated, so there are none).
│           └── <ts4>_create_player_discovered_rooms.exs    + Creates player_discovered_rooms table with the composite PK and FKs.
├── assets/
│   └── css/
│       └── game.css                                           M  REPLACE the existing `.map`, `.map-grid`, `.map-node`, `.map-node.current`, `.map-node.visited`, `.map-edge` CSS rules with new SVG-targeting selectors (`.map-canvas`, `.map-cell`, `.map-cell--current`, `.map-line`, `.map-line--cross-region`, `.map-fog-stub`, `.map-icon-up`, `.map-icon-down`, `.map-affordance-above`, `.map-affordance-below`, `.map-header`). Extend the `.dir-pad` styles for the expanded 3×3 layout + the up/down column. All new colors reference existing CSS variables (`--player`, `--player-dim`, `--ink-faint`, etc.) so the phosphor/sepia/etc. themes inherit map styling without per-theme overrides.
├── config/
│   ├── config.exs                                             M  Add config block for the map renderer: cell_size_px (default 56), viewport_cells (default 11), node_padding_px (default 4). All can be overridden per-environment.
│   └── test.exs                                               # (no override needed; the defaults work for tests)
└── test/
    ├── agenticrealms/
    │   ├── world/
    │   │   ├── direction_test.exs                             M  Add tests for the four new diagonals: parse aliases, opposite/1, to_string/1.
    │   │   ├── direction/
    │   │   │   └── geometry_test.exs                        + delta/1, consistent?/3, unit_vector/1 for all 10 directions.
    │   │   ├── exits/
    │   │   │   └── validator_test.exs                       + Accept/reject matrix per FR-024 — all 10 directions × in-region/cross-region × on-map/off-map × short-distance/long-distance.
    │   │   ├── map_view_test.exs                            + MapView.for_player/1 against handcrafted region fixtures: single-room region, two-wing house (disconnected components on same elevation), multi-floor (above/below affordances), fog stub to undiscovered room, map-hidden room (excluded), cross-region exit (rendered with affordance but destination not drawn), off-map (player in coords-unset room → blank map per FR-003a).
    │   │   ├── region_test.exs                              + Region aggregate execute/2 + apply/2 round-trip.
    │   │   ├── player_test.exs                                M  Add execute/2 tests for RecordRoomDiscovery: first call emits PlayerDiscoveredRoom; subsequent calls for the same room are :ok with no event; apply/2 of PlayerDiscoveredRoom adds the room to discovered_room_ids.
    │   │   ├── projections/
    │   │   │   ├── world_projector_region_test.exs         + RegionCreated projection insertion (idempotent under replay).
    │   │   │   └── world_projector_room_extensions_test.exs + Extended RoomCreated projection: all new fields present + correctly typed; map_x/map_y nullability preserved.
    │   │   └── seed_test.exs                                  M  Assert that the seeded world contains the Blackmire region, the three expected rooms with their authored coords, the Atrium Loft on elevation=1, one map-hidden room, and the cross-region exit. Replaces any earlier seed assertion that referenced removed mock data.
    └── agenticrealms_web/
        ├── components/
        │   └── game_components_mini_map_test.exs           + Render-snapshot tests against three fixture MapViews. Asserts the SVG output contains: (a) the expected number of <rect>/<g> elements for rendered rooms, (b) lines with stroke-dasharray for cross-region exits, (c) fog stubs with the expected gradient stop, (d) up/down icons only where the room has the corresponding exit, (e) NO data-* attributes leaking destination room ids on fog stubs, (f) NO raw elevation integer anywhere in the rendered HTML/SVG.
        └── live/
            └── game_live_maps_test.exs                       + Integration test (`@moduletag :integration`). Exercises US1 (initial render), US2 (move + map updates), US3 (one-way exit lines indistinguishable), US4 (up/down filtering + affordances), US5 (hidden room not visible), US6 (cross-region swap), US7 (hover tooltip on rendered room, generic label on fog stub).
```

**Structure Decision**: New `lib/agenticrealms/world/direction/` and `lib/agenticrealms/world/exits/` directories (small, focused). A new `lib/agenticrealms/world/map_view.ex` sits at the world top level (it's a read-model query module, peer to `queries.ex` and `examine.ex`). A new `lib/agenticrealms/world/region.ex` aggregate sits at the world top level (peer to `room.ex` and `npc_blueprint.ex`). Schemas continue in `lib/agenticrealms/world/schemas/`. UI changes are confined to `game_components.ex` (the `mini_map/1` rewrite + `dir_pad/1` expansion) and a small set of CSS rule swaps. The Application supervision tree gains no new processes.

## Complexity Tracking

> No constitution violations to justify. The data-model extensions and the renderer rewrite are the natural completion of the GUI mock-up that has been a placeholder since feature 001.

| Apparent complexity | Justification |
|---------------------|---------------|
| Destructive migration that purges all pre-existing rooms | Clarification Q3 explicitly authorized this on the basis that the software has no real users yet. The simpler-on-paper alternative (a backfill that assigns Blackmire + elev=0 + coords-unset to all existing rows) was rejected because the seed must still re-author the world coherently to demonstrate US1–US7, and a mixed-state world (some old rooms off-map, new seed rooms placed) is worse for testing and demo than a clean rebuild. |
| SVG-primary renderer (replaces CSS-positioned `<div>` mockup) | Diagonal lines + variable-length connectors + fog-of-war gradients + corner-placed up/down icons + cross-region dashed strokes — all of these are clean primitives in SVG and would require nontrivial CSS gymnastics (rotation, gradients-on-borders, pseudo-elements) and per-line trig in Elixir for the `<div>` approach. SVG keeps the renderer pure, the diff small (LiveView handles SVG attribute diffs natively), and the visual output crisp at all zoom levels. This is the central UI/UX investment the user called out in the plan request. |
| Two parallel suppression mechanisms (`map_visible: false` AND coords-unset) | Both come from the spec (FR-006 + FR-022) and they have different authoring semantics: `map_visible: false` is a wizard-toggleable secrecy flag; coords-unset is an authoring choice for off-map "instance" rooms. The renderer treats them identically (both omit the room and any exits to/from it), so the runtime cost is a single OR in the query — no real complexity penalty for keeping them distinct in the data model. |
| PlayerDiscoveredRoom as an event-sourced fact (vs. derived from event log) | Discovery is queried on every map render and on every movement. Deriving it from the PlayerMoved event log on each read would be O(player movement history) per map render — fine for a single-room player, untenable as the player accumulates movement. A projection table with a composite-PK upsert is the obvious shape and matches the existing `PlayerStateProjector` idiom. |
| Discovery flows through the existing World.Player aggregate (vs. direct projector insert) | Mandatory per the project-wide event-sourcing invariant: every persistent fact in this codebase originates from a command → aggregate → event → projector pipeline. Direct projector inserts into `player_discovered_rooms` would create a back door around event sourcing — the read-model row would no longer be a derived materialization of an event-store fact. Idempotency lives in the aggregate's `discovered_room_ids` MapSet, NOT in a projector pre-check. |
