# Research: Maps

Phase 0 design decisions. Each section opens with a question that surfaced during planning, and closes with the chosen approach + the alternatives considered and why they were rejected.

The user explicitly directed: *"because we support diagonal directions, we need to ensure that the rendering looks good and is easily read by users. The final rendered layout still needs to have a great UI/UX even with diagonals and up/down indicators."* The sections on rendering substrate, viewport, icon placement, fog-of-war, cross-region styling, and the dir-pad expansion all weigh UI/UX quality as the primary criterion.

---

## R1 — Rendering substrate (SVG vs. CSS-positioned `<div>` vs. canvas)

**Decision**: SVG-primary, server-rendered inside the LiveView template. No JS hook required.

**Rationale**:
- Diagonal lines and variable-length connectors are native SVG primitives (`<line>`, `<path>`). With CSS-positioned divs we'd need per-line trig in Elixir to compute `transform: rotate(θdeg)` plus `width: Lpx` (the existing mockup does exactly this for orthogonal-only lines — adding diagonals would multiply the arithmetic and the visual artifacts).
- Fog-of-war gradient stubs render cleanly with `<linearGradient>` + a single line stroke that fades along its length. Doing this in CSS requires a pseudo-element with a gradient background and careful rotation — fiddly and themes badly.
- Up/Down icons inside a room glyph are inline `<path>`s positioned in the room's local SVG coordinate space; no z-index conflicts, no per-icon DOM nodes outside the room group.
- SVG `<title>` is a native hover tooltip. Browsers render it consistently. For richer tooltips (styled with the phosphor/sepia theme palette) we use a separate hover state with a small absolutely-positioned div — but the SVG-native `<title>` is the fallback that satisfies FR-016 even when JS is disabled.
- LiveView diffs SVG attributes natively. Re-rendering on movement is a small diff (typically: the current-room class moves from one `<g>` to another; one or two new `<g>` elements appear if a room is newly discovered). No JS coordination.
- Crisp at all browser zoom levels. The map panel honors `--density` UI tweak via a CSS variable on `<svg width/height>`.

**Alternatives considered**:
- **CSS-positioned `<div>` (current mockup)**: works for orthogonal lines, breaks down for diagonals (you can rotate a div but variable-length diagonal stitching looks jagged where lines meet rooms). Fog gradient and corner icons are awkward.
- **HTML5 `<canvas>` via JS hook**: gives the most rendering control but requires a JS hook on every map update, breaks LiveView's render-diff model, and adds a second source of truth (canvas state vs. LiveView state).
- **CSS Grid with auto-placement**: tempting for orthogonal layouts but does not handle diagonals at all (a NE exit would require either a rotated child or a separate overlay element — same problems as the rotated-div approach).

---

## R2 — Coordinate plane, viewport, and centering

**Decision**: Fixed cell size (default 56 px square) with a fixed-window viewport (default 11 × 11 cells) centered on the player's current room. The SVG `viewBox` is set dynamically so the player's room sits at the center of the visible area. Discovered rooms outside the 11×11 window are not rendered (no scroll, no pan, no zoom in v1).

**Rationale**:
- A fixed cell size keeps every room glyph the same physical size on screen regardless of how the player's region is laid out (a region with 4 rooms and a region with 200 rooms render rooms at identical sizes, which avoids the disorienting auto-zoom snap that comes with "fit-to-bounds" layouts).
- An 11×11 window covers a 5-cell radius around the player — wide enough to show meaningful surroundings, narrow enough that even a NE exit at distance 5 still fits on screen.
- The center is locked to the player. Movement causes the player's room to stay centered; OTHER rooms appear to shift one cell in the opposite direction. This is the same convention used by every roguelike / overhead RPG and is the lowest-cognitive-load layout for movement-driven map updates.
- No scrolling for MVP keeps the renderer simple and the interaction model unambiguous. A future iteration can add a "world map" expanded view that scrolls.

**Alternatives considered**:
- **Auto-fit to discovered bounding box**: rooms shrink/grow as the player discovers more of the region. Disorienting on every discovery; rejected.
- **Player-centered with continuous scroll/pan during movement**: animation budget for movement is already busy (game log scroll, room name update, presence panel refresh). A snap-center on each move is simpler and equally readable.
- **Tile-tessellated hex grid**: would render diagonals more naturally but conflicts with the 8-cardinal-direction model in the spec (which presumes a square grid where NE is a 45° diagonal).

**Open knobs (in `config :agenticrealms, AgenticRealms.MapRenderer`)**:
- `cell_size_px` (default 56)
- `viewport_cells` (default 11 — must be odd so a center cell exists)
- `node_padding_px` (default 4 — gap between the room glyph and its cell edge, so lines have visible run-up)

---

## R3 — Room glyph design (current vs. discovered vs. fog stub vs. hidden)

**Decision**: Each rendered room is an SVG `<g>` containing a `<rect>` (48 × 48 px inside the 56 px cell, 4 px padding on each side) with rounded corners (`rx="4"`). The fill and stroke come from CSS variables so themes (phosphor, sepia, etc.) cascade automatically.

**Visual states**:
- **Current room**: bright fill (`var(--player)`) with a soft outer glow (`filter: drop-shadow(...)` referencing `var(--player)`).
- **Discovered, non-current**: subdued fill (`var(--bg-inset)`), stroke `var(--ink-dim)`.
- **Hovered**: stroke brightens to `var(--player)`, no fill change. Combined with a styled tooltip showing the room's friendly name (FR-016).
- **Fog-of-war stub endpoint**: NOT a `<rect>` — drawn as a hatched cloud (a small `<path>` with a `pattern` fill, approximately a 24 × 24 px region at the end of the stub line). Carries no room name in DOM, no `<title>` element, no `data-*` attribute that names the destination (FR-007, FR-017).
- **Hidden room**: not rendered at all (FR-006). The renderer's room-filter at the `MapView` layer never emits hidden rooms; the SVG layer has no awareness of their existence.

**Up/Down icons**:
- **Up icon**: small chevron-up SVG path at the top-right corner of the room rect (positioned inside the rect, 6 × 6 px, padded 3 px from each edge).
- **Down icon**: chevron-down at the bottom-right corner.
- A room with both: both icons render in their respective corners. They never conflict because the corners are physically separate.
- Color: `var(--ink-dim)` normally; brightens to `var(--player)` on hover of the room.

**Above/Below affordances** (FR-011):
- Two small chevron-pips next to the region name in the map header.
- `↑` pip: visible only when the player has discovered at least one room at a higher elevation in the current region.
- `↓` pip: visible only when the player has discovered at least one room at a lower elevation.
- No number, no count, no integer (FR-012). Just presence/absence.
- Color: `var(--ink-dim)` normally; `var(--player-dim)` when the player has rooms at that elevation (visual hint that those slices exist).

**Alternatives considered**:
- **Up/Down as line segments off the top/bottom edges** (mimicking compass exits): visually confusable with NE/N/NW lines. Rejected per FR-009 spec text ("Up and Down must be represented as an icon associated with the room").
- **Single corner badge with both arrows stacked**: tighter visually but ambiguous when only one is present. Rejected.
- **Above/Below as a side-panel legend**: harder to spot at a glance. The in-header pips are immediate and reflect the player's current elevation context.

---

## R4 — Exit line rendering (intra-region, cross-region, fog stub)

**Decision**: All exit connections are SVG `<line>` elements drawn from the center of the source room to either (a) the center of the target room (intra-region, both discovered, both mapped) or (b) a point one cell into the destination direction (fog stub or cross-region affordance terminator). Line length is the natural geometric distance between endpoints (FR-025 / SC-014).

**Stroke styles**:
- **Intra-region, normal**: `stroke="var(--ink-dim)"`, `stroke-width="2"`, no dash. Carries no information about exit directionality (FR-005 / SC-003).
- **Cross-region (FR-008)**: `stroke="var(--player-dim)"`, `stroke-width="2"`, `stroke-dasharray="4 3"` (subtle dash). A small "portal" glyph (4 × 4 px diamond) sits at the destination end of the line. The portal glyph carries NO room name or region name (the player only learns the destination region by going through the exit — per FR-008 spec text).
- **Fog-of-war stub (FR-007)**: half-length line (the geometric distance one cell into the direction), with `<linearGradient>` from full opacity at the source end to ~10% opacity at the fog end. Terminates in the hatched cloud described in R3.

**Line endpoints**:
- Always center-of-room → center-of-target. The stroke runs underneath the room's `<rect>` (because the room `<g>` is z-order-after the line `<g>`), so the visible portion is exactly the run between rooms.
- For diagonals, the line is a true 45° angle (`atan2(dy, dx) = 45°` for NE), not a stepped/L-shaped path. The user's emphasis on diagonals rendering well drives this.

**One-way exit handling**:
- A pair of rooms connected by either one exit OR two reciprocal exits MUST render as a single line (FR-004). The renderer deduplicates by canonicalizing the pair as `{min(room_id), max(room_id)}` before drawing.
- When only one direction is authored (e.g., a one-way trap), the visual is identical. The line carries no arrowhead, no asymmetry (FR-005 / SC-003).

**Alternatives considered**:
- **Stepped paths for diagonals** (Manhattan-routed): legible at zoom but ugly and confusing for the 8-direction model. Rejected.
- **Curved Bezier connections**: pretty but obscures the direction-of-axis relationship and the line-length-as-distance signal (R5 below). Rejected.
- **Different color per direction**: leaks one-way information at the renderer level. Rejected on FR-005 grounds.

---

## R5 — Long-distance exits (bridges)

**Decision**: A single exit with a coordinate distance > 1 along its axis renders as a single longer line — exactly proportional to the geometric distance (FR-025). No filler "ghost cells" between the two rooms.

**Rationale**:
- This is the most direct interpretation of clarification Q4's "flexible distance" rule. A 5-cell bridge looks like a 5-cell-long line; players can immediately see the spatial scale.
- The viewport's 11×11 window plus the player-centered convention means a long bridge that exits the viewport will appear to "lead off the edge" of the visible map. This is acceptable — when the player walks the bridge, the viewport re-centers and the bridge becomes fully visible again from the destination side.

**Overlap with intervening rooms**: per the spec's assumption section, long-distance exits may visually overlap rooms in intervening cells. Wizards are responsible for avoiding such overlaps when they matter. The renderer makes no special accommodation — the line is drawn under the room glyphs, so a bridge passing through a cell that has a room renders the line behind the room's rect.

---

## R6 — Hover tooltip styling and accessibility

**Decision**: SVG-native `<title>` element on every rendered room `<g>`, augmented by an HTML tooltip rendered with CSS for visual polish.

**Why both**:
- `<title>` is the accessibility baseline (screen readers, keyboard nav, FR-016 minimum).
- The CSS tooltip provides themed visual polish (phosphor green text on a translucent dark background, matching the rest of the UI). Implemented as a `<div class="map-tooltip">` positioned absolutely relative to the SVG by a tiny LiveView ColocatedHook (~10 lines of JS) that mirrors `mousemove` over each room into a pushed `tooltip:show`/`tooltip:hide` server event with the room's display name.
- For fog stubs and cross-region portal glyphs: NO `<title>`, NO data-attribute, NO custom tooltip — they are silent on hover (FR-017).

**Alternatives considered**:
- **Pure CSS tooltip via `:hover` + `::after`**: works but doesn't allow the tooltip to overflow the SVG element cleanly, and styling for off-edge tooltips becomes a quirk per browser. The JS-assisted approach is ~10 lines and gives perfect control.

---

## R7 — Dir-pad expansion (4 → 10 directions)

**Decision**: 3 × 3 compass pad (8 cardinal buttons + a center "look" button) and a separate vertically-stacked Up/Down column to the right of the compass.

```text
┌─────┬─────┬─────┐
│ NW  │  N  │ NE  │   ┌────┐
├─────┼─────┼─────┤   │ Up │
│  W  │ look│  E  │   ├────┤
├─────┼─────┼─────┤   │ Dn │
│ SW  │  S  │ SE  │   └────┘
└─────┴─────┴─────┘
```

**Rationale**:
- The 3×3 compass is the universally-recognized "look around" pad. Players who used the 4-direction version already know where N/S/E/W are; NE/NW/SE/SW filling the corners is intuitive.
- Up/Down sit separately because they aren't compass directions — visually conflating them with the rotation pad invites errors.
- The center cell could be empty, but a "look" button makes for a useful affordance: tap to re-look at the current room (the existing `look` command).

**Sizing**: each button is `square(--dir-pad-button-size, 32 px)`. Total dir-pad footprint ≈ 100 × 100 px including gap; the Up/Down column ≈ 32 × 72 px. Fits in the existing left-side panel under the map without crowding.

**Button labels**: single-letter for cardinals (N, S, E, W), two-letter for diagonals (NE, NW, SE, SW), spelled-out for vertical ("Up", "Dn"). Lowercase under-glow for unavailable directions (no exit that way).

**Accessibility**: each button carries an `aria-label` with the full direction name, and a `title` for hover.

**Alternatives considered**:
- **Inline 5×5 with up/down in the middle row**: visually awkward; vertical directions don't belong in the compass plane.
- **Drop-down menu for diagonals**: hides them behind a click. Rejected — diagonals deserve top-level access for a game that authors them.
- **Keyboard-only diagonals (no button)**: leaves casual players without affordance. Rejected.

---

## R8 — Player discovery: storage and emission

**Decision**: An event-sourced fact (`PlayerDiscoveredRoom`) projected to a `player_discovered_rooms` read model table. Emission flows through a new `World.Player` aggregate via a `RecordRoomDiscovery` command — the aggregate is mandatory, NOT a recommendation.

**Project-wide invariant** (also captured in [contracts/discovery.md](./contracts/discovery.md)):

> Every persistent fact in this project MUST originate from a command → aggregate → event → projector pipeline. No code path may insert into `player_discovered_rooms` (or any other event-sourced read-model table) directly. There is no documented "simpler fallback" — direct projector inserts that bypass event sourcing are forbidden, even when the row looks trivially idempotent.

**Why event-sourced**:
- Matches the project's universal idiom. Every persistent fact in this codebase is backed by a domain event.
- Survives replay: re-running the projector reconstructs the full discovery set from the event log.
- Single source of truth: the event store. The read-model row is a derived materialization, never an independent claim.
- Cheap on read: a composite-PK upsert is `O(1)` per emission; queries are indexed lookups.

**Emission path**:
- `PlayerStateProjector` handles `PlayerSpawned` and `PlayerMoved`. After the existing `current_room_id` update, it dispatches `RecordRoomDiscovery(player_id, room_id)` UNCONDITIONALLY against the `World.Player` aggregate.
- The aggregate's `execute/2` consults its in-process `MapSet` of already-discovered room ids. If the room is already discovered, NO event is emitted (the aggregate returns `:ok` without producing an event). Otherwise it emits `PlayerDiscoveredRoom`.
- The projector then writes the row via the existing `on_conflict: :nothing` clause — but the row will only ever appear if the event ran, which only happens for first-discovery events.
- The projector NEVER consults `player_discovered_rooms` directly to gate emission — the aggregate's `MapSet` is authoritative for idempotency. This keeps the event-sourced model the single source of truth and prevents read-model drift from causing skipped or duplicate emissions.
- Dispatching a command from a projector handler is a known pattern in Commanded (the project already uses it for `spawn_npc_clone`'s synthetic-blueprint backfill).

**Alternatives considered**:
- **Discovery as an array column on `player_state`**: simpler shape but mutable hot row that grows unboundedly; bad indexing for "is room X discovered by player Y?" queries. Rejected.
- **Discovery derived from `PlayerMoved` event scan on every map render**: O(player movement history) per render; rejected.
- **Direct insert from `PlayerStateProjector`** (no event): forbidden by the project-wide invariant above. Not considered as a documented fallback — there is no fallback.

---

## R9 — Direction module extension shape

**Decision**: A single edit to `World.Direction` adds `:northeast`, `:northwest`, `:southeast`, `:southwest` to `@canonical`, with parse aliases (`"ne"`, `"northeast"`, `"nw"`, `"southwest"`, ...), opposite mappings (NE↔SW, NW↔SE), and `to_string/1` cases. A NEW `World.Direction.Geometry` module owns the coordinate-delta logic:

```elixir
@spec delta(direction()) :: {:planar, {dx_sign, dy_sign}} | {:vertical, dz_sign}
@spec consistent?(direction(), source_room :: %Room{}, target_room :: %Room{}) :: boolean
@spec unit_vector(direction()) :: {dx :: float, dy :: float}
```

**Why separate `Geometry`**:
- `Direction` is currently a pure name/parse module with no coordinate awareness. Adding geometric logic to it would couple it to the new map fields on `Room` and break the existing module's clean shape.
- `Geometry.consistent?/3` is the single source of truth for FR-024. The `Exits.Validator` and any future authoring UI both consume it.
- `Geometry.unit_vector/1` returns the SVG-line-angle vector for the renderer (e.g., `{1, -1}` for NE in screen coords).

---

## R10 — Test fixture seeding for `MapView` unit tests

**Decision**: A test helper module `AgenticRealms.MapFixtures` builds canonical `Region`/`Room`/`Exit`/`PlayerDiscoveredRoom` fixtures via direct Repo inserts (bypassing the command pipeline). Each fixture function returns a map of named ids so tests can assert specific rooms by alias.

**Fixtures**:
- `single_room/0` — one room, one region, one player who has discovered just that room.
- `linear_three/0` — three rooms in a row (A↔B↔C), all discovered, demonstrating connecting lines.
- `two_wing_house/0` — six rooms across two elevations, demonstrating disconnected components on elevation 1 (US4 acceptance scenario 5).
- `multi_floor/0` — three rooms stacked vertically (elev 0/1/2), used for up/down icon + above/below affordance tests.
- `fog_stub/0` — two rooms connected by an exit; player has discovered only the source.
- `hidden_room/0` — three rooms; one of them is `map_visible: false`; tests that the renderer omits both the room and its connecting line.
- `cross_region/0` — two regions (Blackmire + Hollowvale) with an exit between them; player has discovered rooms in both.
- `off_map/0` — player stands in a room with `(map_x, map_y) = nil` (or in a `map_visible: false` room); tests FR-003a.

**Why direct Repo inserts**:
- Bypassing the command pipeline avoids needing to validate every fixture exit against `Exits.Validator` (which would force fixtures to be geometrically pristine even for tests that don't care). Direct inserts give the test full control.
- The validator gets its own focused test file (`exits/validator_test.exs`) covering accept/reject cases against synthetic inputs — no fixture coupling required.

---

## R11 — Out-of-scope (documented to head off scope creep)

The following are explicitly NOT in this feature, even though they're plausibly related:

- **Click-to-move on the map** — FR-018 forbids it.
- **Wizard UI for placing rooms** — coordinates are authored via seed/commands only in v1. The wizard's room-creation UI is a separate future feature.
- **Region renaming UI** — names are set at region-creation time; no rename flow in v1.
- **Scrollable / zoomable map** — fixed 11×11 viewport for MVP.
- **World map (full-region overview)** — only the player's neighborhood is shown.
- **Discovery sharing between players** — discovery is strictly per-player.
- **Auto-layout from exit topology** — coordinates are explicit; no auto-derive.
- **Wormhole/teleporter exit type** — simulated via off-map rooms per the spec's assumption.
- **Object/NPC pins on the map** — only rooms are rendered; the spec is silent on entities-on-map.
- **Real-time map updates from wizard edits while a player has the map open** — handled implicitly by LiveView's re-render-on-PubSub, but no dedicated channel is added for wizard-edit events in this feature.
