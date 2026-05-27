# Feature Specification: Maps

**Feature Branch**: `012-maps`
**Created**: 2026-05-26
**Status**: Draft
**Input**: User description: "maps — Make real the map overlay that is currently just a mockup in the UI. All rooms can either be visible to the map or hidden/invisible (default: visible). Every room belongs to a single map (called a 'region' in the UI) that has a friendly name. Exits leading to invisible rooms do not appear on the map. Exits as defined in data are directional and may be one-way, but the map never differentiates — a connecting line is always just a line, so one-way traps are not spottable from the map (though dead-ends — a line into a terminating room — are fine). The map supports all 8 compass directions plus up and down. Up/Down are represented as icons on the room, and a room may have both. Undiscovered rooms do not appear, but exit lines extend from discovered rooms to indicate that something lies that way (fog-of-war affordance). Hovering a room shows its name in a tip. Click-to-move is NOT in scope. Cross-region exits get a visual affordance. Crossing regions swaps the map overlay and the region label. Moving up or down filters the map to that elevation; elevation is an integer z-index defaulting to 0; the raw number is NEVER displayed. Two unconnected sets of rooms on the same elevation appear as separate connected components. The UI must indicate that discovered rooms exist above or below the current elevation when applicable."

## Clarifications

### Session 2026-05-26

- Q: How are rooms positioned on the map plane within a region — explicitly authored coordinates per room, or derived from exit-direction topology? → A: A — each room has explicit authored grid coordinates (x, y) within its region. Coordinates are optional metadata on a room; a room with NO coordinates set does not appear on the map at all (treated as off-map for rendering, same effect as map-hidden). Coordinates of (0, 0) are a valid, on-map position — NOT a sentinel for "no coordinates set."
- Q: When a player is standing in an invisible (map-hidden) or unmapped (no-coordinates) room, what does the map overlay show? → A: A — the map shows the region name and an otherwise blank map area. No room squares are drawn (no other discovered rooms in the region, no fog stubs, no "you are here" marker). The player is effectively off the map for as long as they remain in that room.
- Q: How are regions represented in the data model — first-class entity, string field on Room, or hybrid slug registry? → A: A — Region is a first-class entity (own schema/table) with an id and a friendly display name. Rooms reference their region by FK. Region supports future region-level metadata. The seed/built-in content is all part of a single region named **Blackmire**. (Future feature: when wizards gain the ability to create rooms, a newly created room inherits its region from the wizard player's current room.)
- Q: Can two rooms share the same `(x, y)` coordinate within a region, and does elevation factor into uniqueness? → A: A — a room's on-map position is uniquely identified by the tuple `(region, elevation, x, y)`. New rooms cannot be created (and existing rooms cannot be moved) into a coordinate already occupied by another room at the same `(region, elevation)`. Different elevations may reuse the same `(x, y)` (multi-story alignment is allowed). Enforced at the data layer (e.g., a unique constraint on the four-column tuple, accounting for the optional nature of x/y — the constraint applies only when coordinates are set).
- Q: Seed and migration behavior for existing rooms when this feature lands? → A: A — seed scripts author region (Blackmire) + elevation (0) + explicit `(x, y)` for all seed rooms so the map works on fresh install. ALL pre-existing rooms are purged entirely as part of this feature — no backfill path. This is safe because the software has not yet been used by real users; there is no production world state to preserve.
- Q: Must exit `direction` be geometrically consistent with the source and target rooms' coordinates? → A: A, modified — strict DIRECTION consistency with FLEXIBLE DISTANCE. An exit's direction must point along the correct axis from source to target (a "north" exit requires target.y to be less than source.y with target.x unchanged; an "east" exit requires target.x greater than source.x with target.y unchanged; diagonals require equal-magnitude Δx and Δy in the matching signs; "up"/"down" require Δ(x,y) = (0, 0) and target.elevation > or < source.elevation). The DISTANCE along that axis is any positive integer ≥ 1 — so a single exit can span multiple cells (a bridge over a chasm, a long corridor) without filler rooms. The rendered line length on the map is proportional to the distance. The system rejects exit create/edit that violates direction consistency. The check applies only when BOTH source and target have coordinates set; an exit from or to an off-map (no-coords) room skips geometric checking, which is the supported pattern for simulating wormholes / teleporters (e.g., a vertical exit from an off-map room to a distant elevation).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A player opens the map and sees their actual surroundings (Priority: P1)

A player opens the map overlay (replacing the current static mockup). The overlay shows the rooms in their current region that they have personally discovered, drawn on a 2D plane with their current room visibly highlighted. The region's friendly name (e.g., "Blackmire") appears above the map. Exits between discovered rooms are drawn as simple connecting lines.

**Why this priority**: This is the MVP — without a real, player-specific, region-scoped map drawn from actual world data, none of the richer behavior (fog-of-war, elevation, region transitions, hidden rooms) has anything to attach to. It also retires the hardcoded mockup, which is the explicit driver of this feature.

**Independent Test**: A freshly seeded player who has only stood in one room sees the map overlay show exactly that one room, highlighted as the current room, with the correct region name in the header — no other rooms appear, no other regions appear.

**Acceptance Scenarios**:

1. **Given** a player whose only discovered room is the Gilded Kraken (in region "Blackmire"), **When** the player opens the map overlay, **Then** the map shows exactly one room square (the Kraken), highlighted as the current location, and the region header reads "Blackmire".
2. **Given** a player who has discovered three connected rooms (A↔B, B↔C) all in the same region and same elevation, **When** the player opens the map overlay, **Then** all three squares are rendered with two undirected lines connecting them, and the current room is the only one highlighted as "you are here".
3. **Given** two players standing in the same room but with different discovery histories, **When** each opens the map overlay, **Then** each sees only their own discovered rooms — discovery is per-player, not shared.

---

### User Story 2 — The map updates as the player moves (Priority: P1)

When the player moves from one room to an adjacent room, the map overlay updates: the previous room loses the "you are here" highlight, the new room gains it, and — if the new room had not been seen before — it appears on the map for the first time. Exit lines to the newly discovered room collapse from fog-of-war stubs into proper connections.

**Why this priority**: A static "you only see where you've been" map that doesn't update on movement is useless. Movement-driven discovery is the loop that builds the map.

**Independent Test**: Stand in a room with one undiscovered neighbor visible as a fog stub. Move to that neighbor. The stub resolves to a full room square highlighted as "you are here", the previous room loses its highlight, and the connection between them is a normal line.

**Acceptance Scenarios**:

1. **Given** a player in room A with a discovered exit to room B (B not yet discovered, shown as a fog stub), **When** the player moves to B, **Then** B appears as a full room square highlighted as the current location, A's highlight is removed, and the A↔B line is rendered as a normal connection (no longer ending in a fog stub).
2. **Given** a player who moves into an already-discovered room, **When** the move completes, **Then** the "you are here" highlight moves to the new room with no other layout changes.
3. **Given** the map overlay is closed, **When** the player moves between rooms, **Then** reopening the overlay reflects all movement that happened while it was closed (no stale state).

---

### User Story 3 — One-way exits and undiscovered rooms never leak information through the map (Priority: P1)

The map deliberately conceals two pieces of information that would otherwise spoil gameplay: (a) the direction of one-way exits — every connecting line on the map looks identical regardless of whether the underlying exit is bidirectional or one-way, and (b) the identity of undiscovered destinations — an exit leading toward a room the player has not yet visited appears as a line ending in a fog-of-war affordance, with no room name or room shape revealed.

**Why this priority**: Without these information-hiding rules in place from the start, the map actively undermines the core game design (one-way traps surprise players; undiscovered areas are mysterious). Building the map without these rules would force a behavior change later that affects every rendered exit.

**Independent Test**: Author two rooms connected by a single one-way exit (A→B, no return). From a player who has discovered both, the map line between them is visually indistinguishable from a two-way connection elsewhere on the map. Separately, author a room with an exit to an undiscovered room; the map shows a line extending from the discovered room ending in a fog-of-war marker — no room name appears even on hover of the fog marker (or the fog marker has no name tip at all).

**Acceptance Scenarios**:

1. **Given** a player who has discovered rooms A and B connected by a one-way exit A→B, **When** the player views the map, **Then** the line drawn between A and B is visually identical to every other connecting line on the map (no arrowheads, no asymmetric styling, no directional cue of any kind).
2. **Given** a player in room A with an exit toward an undiscovered room X, **When** the player views the map, **Then** a line extends from A in the appropriate direction, ending in a fog-of-war marker that does NOT reveal X's name, X's shape, or any other identifying detail.
3. **Given** an exit from A that leads to a room that the player will never be able to return from (a dead-end terminating room which the player has discovered), **When** the player views the map, **Then** the terminating room appears as a normal room square at the end of a normal connecting line — "dead end" is acceptable visual information; "one-way trap" is not.

---

### User Story 4 — Vertical exits and elevation filtering (Priority: P2)

Rooms can be connected by up and down exits in addition to the 8 compass directions. On the map, an "up" exit is shown as an icon on the room itself (not a line going off-grid); a "down" exit is shown as a separate icon on the same room. A room may have both an up and a down icon at the same time (e.g., a middle landing on a spiral staircase). When the player ascends or descends, the map filters to show only the rooms on the player's new elevation — the previous floor's rooms disappear from view entirely. The map shows an affordance ("there are discovered rooms above and/or below") but never displays the raw elevation number.

**Why this priority**: Multi-floor buildings are a real authoring need (spiral staircases, towers, dungeon levels) and the spec calls them out explicitly. Without elevation filtering, a multi-floor structure would either pile floors on top of each other in 2D or require a different overlay entirely.

**Independent Test**: Author a two-floor structure: room A at elevation 0 with an "up" exit to room B at elevation 1. Discover both. Standing in A, the map shows only A with an up icon; standing in B, the map shows only B with a down icon. In both states, the elevation-up-or-down affordance is visible, but no integer is shown anywhere in the UI.

**Acceptance Scenarios**:

1. **Given** a discovered room A at elevation 0 with an "up" exit to a discovered room B at elevation 1, **When** the player is standing in A, **Then** the map shows A on the elevation-0 plane with an up icon, but B is not drawn on this view; an "above" affordance appears.
2. **Given** the same setup, **When** the player goes up to B, **Then** the map switches to show only the rooms at elevation 1 (B is highlighted with a down icon); A is not drawn; a "below" affordance appears.
3. **Given** a middle-landing room C at elevation 1 that has both an up exit to D (elev 2) and a down exit to E (elev 0), **When** the player views the map while standing in C, **Then** C displays both an up icon and a down icon simultaneously, with no other affordance needed to distinguish them.
4. **Given** any view of the map at any elevation, **When** the player inspects the UI, **Then** no raw integer elevation value is shown anywhere on the map overlay or its header.
5. **Given** two disconnected wings of a house, both with discovered rooms on elevation 1 (the wings only connect on elevation 0), **When** the player views the elevation-1 map, **Then** both wings appear as separate connected components in the same view with no line between them.

---

### User Story 5 — Hidden rooms are invisible to the map (Priority: P2)

A wizard can designate a room as map-hidden (the default is map-visible). Map-hidden rooms never appear as squares on the map, and any exit leading toward a map-hidden room is not drawn (the source room appears to have no exit in that direction at all — neither a connecting line nor a fog-of-war stub). Movement through such exits still works normally via cardinal commands; only the map representation is suppressed.

**Why this priority**: This is the wizard's primary tool for secret areas (a hidden trapdoor, a concealed corridor). It's distinct from undiscovered rooms — an undiscovered room teases the player with a fog stub, but a hidden room offers no map hint at all. Without this, secret areas leak through the map.

**Independent Test**: Author room A with two exits: one north (to map-visible room B, also discovered) and one east (to map-hidden room C, also discovered). The map shows A with a connection to B going north, but no connection going east — the east side of A looks blank, identical to a room with no eastern exit. C is not rendered anywhere.

**Acceptance Scenarios**:

1. **Given** a discovered room A with an exit east to a discovered but map-hidden room C, **When** the player views the map, **Then** A appears with no east-going line and no east fog stub — visually indistinguishable from a room with no east exit, and C is not rendered.
2. **Given** a wizard toggles room C from hidden to visible after the player has already discovered both A and C via cardinal movement, **When** the player next views (or refreshes) the map, **Then** C appears as a normal discovered room square and the A→C connection is drawn.
3. **Given** a player attempts to move east from A toward map-hidden room C using the cardinal command, **When** the command resolves, **Then** the player is successfully moved into C — map visibility does not affect movement.

---

### User Story 6 — Crossing into another region swaps the map (Priority: P2)

When a player moves through an exit whose destination is in a different region from the source, the map overlay swaps to show the new region: the region name in the header updates, and the rendered rooms are the player's discovered rooms in the new region at the player's new elevation. Additionally, while standing in the source region, any exit that crosses into another region carries a visual affordance distinguishing it from an intra-region exit.

**Why this priority**: Multi-region worlds are how the game scales (one map gets cluttered; regions break content up). Without smooth region transitions on the map, the world's structure breaks at every region boundary.

**Independent Test**: Author two regions, Blackmire and Hollowvale, with a single exit between them (Blackmire.Gate → Hollowvale.Entrance). Discover rooms in both. Standing in Blackmire.Gate, the map shows the Blackmire map with the gate-room marked, and the cross-region exit carries a visible distinguishing mark. Moving through the gate switches the map header from "Blackmire" to "Hollowvale" and replaces the rendered rooms with the Hollowvale discoveries.

**Acceptance Scenarios**:

1. **Given** a player standing in a Blackmire room with an exit east leading into Hollowvale, **When** the player views the map, **Then** the eastward exit line carries a distinct cross-region affordance (visually different from a normal intra-region line), the destination room in Hollowvale is NOT rendered on the Blackmire map, and the header still reads "Blackmire".
2. **Given** the same player, **When** the player moves east into Hollowvale, **Then** the map overlay swaps so that the header reads "Hollowvale" and only the player's discovered Hollowvale rooms at the new elevation are rendered.
3. **Given** the cross-region exit is one-way (Blackmire→Hollowvale only), **When** any player views the map from either side, **Then** the cross-region affordance is the same — directional information about the cross-region exit is still concealed per US3.

---

### User Story 7 — Hover tooltips reveal room names (Priority: P3)

Hovering over any rendered room square on the map shows the room's friendly name in a tooltip. Fog-of-war stubs (undiscovered destinations) do NOT reveal room names; hidden rooms do not appear at all so no tooltip applies to them.

**Why this priority**: A nice-to-have polish that makes the map self-documenting. It's secondary to the structural correctness of what gets drawn at all — without US1–US6 working, a tooltip has nothing useful to label.

**Independent Test**: Hover over the highlighted "you are here" room; the tooltip shows the room's friendly name. Hover over an undiscovered fog stub; either no tooltip appears, or a generic "undiscovered" tooltip appears (never the actual room's name).

**Acceptance Scenarios**:

1. **Given** a map view with several rendered room squares, **When** the player hovers over a discovered room square, **Then** a tooltip appears with that room's friendly name (e.g., "The Gilded Kraken").
2. **Given** a map view with at least one fog-of-war stub, **When** the player hovers over the fog stub, **Then** no tooltip reveals the destination room's name — the stub is either un-hoverable or shows only a generic "unknown" indicator.

---

### Edge Cases

- **Player has discovered zero rooms (impossible after first spawn)**: A player has by definition at least one discovered room — the one they spawned into — so the map always has something to render. This is not a state the system has to handle separately.
- **Player is standing in an invisible (map-hidden) or unmapped (no-coordinates) room**: The map overlay shows only the region name; no room squares, no fog stubs, no "you are here" marker. The map is effectively blank until the player moves into a mapped, visible room. This is intentional — the player is "off the map" while in such a room.
- **Room exists in a region but has no coordinates set**: The room never appears on the map (no square, no exit lines to or from it on the map), regardless of map-visibility or discovery. This is a parallel suppression mechanism to map-hidden, useful for rooms that exist in the world (e.g., scratch rooms, instance interiors) but should not occupy a position on any map.
- **Room has coordinates (0, 0)**: (0, 0) is a valid, on-map position. It is NOT interpreted as "no coordinates" — the room renders normally at the origin of its region's coordinate plane.
- **Wizard hides a previously visible room that the player has discovered**: The room and its connecting lines disappear from the map immediately on next render. The discovery record is NOT erased; if the wizard re-shows the room, it reappears as a discovered room with no need to re-visit.
- **Wizard shows a previously hidden room that the player has already visited (via cardinal command) while it was hidden**: Visiting marks discovery regardless of map visibility, so when shown the room appears as already-discovered.
- **Two unconnected wings on the same elevation in the same region**: Both render in the same view as separate connected components; no line is drawn between them; the player can see rooms from both wings on the same map even though they cannot walk between them at this elevation.
- **A room is its own region (single-room region)**: Map shows one square, the region name in the header, no exits or only cross-region affordance exits.
- **A room has an exit leading to a hidden room which the player has also discovered**: The hidden-room rule trumps the discovered-room rule — neither the room nor the line is drawn.
- **Multiple exits in the same direction (e.g., two "up" exits)**: Out of scope — a room is assumed to have at most one exit per direction. Authoring tools should prevent duplicates.
- **An exit's direction is "up" or "down" and the destination is on the same elevation, or "north" and the destination is on a different elevation**: Now explicitly rejected per FR-024 — direction must match the geometric relationship between source and target rooms whenever both have coordinates set.
- **A long-distance exit (a bridge or long corridor that spans multiple cells)**: Permitted by FR-024 (distance ≥ 1 along the direction axis) and rendered as a longer-than-unit line per FR-025. Wizards may use this to model bridges, ravines, or long stretches of geography without creating filler rooms players must traverse.
- **A "wormhole" or teleport-like exit**: There is no dedicated wormhole exit type. The supported pattern is an off-map (no-coords) hub room with vertical or other exits whose targets bypass the geometric check via FR-024's "skip check when either room is off-map" clause. Players pass through the off-map room and see a blank map for one tick, which masks the spatial jump.

## Requirements *(mandatory)*

### Functional Requirements

**Map composition**

- **FR-001**: The map overlay MUST render only those rooms that are (a) in the player's current region, (b) at the player's current elevation, (c) personally discovered by the player, (d) NOT marked map-hidden, AND (e) have explicit (x, y) coordinates set within their region. Rooms missing any of these properties MUST NOT be drawn as squares on the overlay.
- **FR-002**: Each rendered room MUST be drawn as a square (or equivalent shape) and the player's current room MUST be visually distinguished as the current location.
- **FR-003**: Each region MUST have a friendly display name; the map overlay MUST display this name as a header above the map (e.g., "Blackmire").
- **FR-003a**: When the player's current room is map-hidden OR has no coordinates set ("off-map"), the map overlay MUST display only the region name as a header, with the map drawing area otherwise blank — no room squares (including the player's other discovered rooms), no fog stubs, no "you are here" marker, no above/below affordances. The map remains blank for the duration the player occupies an off-map room.

**Exits and information hiding**

- **FR-004**: For each pair of rendered rooms in the current view that are connected by an exit (in either direction), exactly one undirected line MUST be drawn between them.
- **FR-005**: The map MUST NOT render any visual cue that distinguishes a one-way exit from a two-way exit (no arrowheads, no asymmetric line styling, no direction-of-travel indicator).
- **FR-006**: Any exit whose destination is a map-hidden room OR a room with no coordinates set MUST NOT be rendered at all (no line, no fog stub, no affordance). The source room MUST visually look the same as a room with no exit in that direction.
- **FR-007**: Any exit whose destination is a map-visible room that the player has NOT yet discovered MUST be rendered as a line extending from the source room in the exit's compass direction, terminating in a fog-of-war marker that does NOT reveal the destination room's identity (no name, no shape, no other identifying detail).
- **FR-008**: Any exit whose destination room is in a DIFFERENT region from the source MUST carry a distinct cross-region visual affordance. The destination room MUST NOT be rendered on the source region's map view, regardless of discovery state.

**Vertical exits and elevation**

- **FR-009**: A room with an "up" exit MUST display an up-icon on or adjacent to the room square; a room with a "down" exit MUST display a down-icon on or adjacent to the room square. A room with BOTH MUST display both icons simultaneously, without one obscuring the other.
- **FR-010**: When the player's current room changes elevation, the map view MUST update to show only rooms at the new elevation (the previous elevation's rooms MUST disappear from view).
- **FR-011**: The map MUST display an affordance indicating that the player has discovered rooms above the current elevation, and a separate affordance indicating discovered rooms below the current elevation. Each affordance MUST appear ONLY when at least one such room exists.
- **FR-012**: The map UI MUST NOT display the raw elevation integer (or any direct numeric representation of it) anywhere in the overlay or its header.

**Discovery**

- **FR-013**: A room MUST be marked as discovered for a given player the first time that player enters it. Discovery state MUST be persisted per-player and MUST NOT be shared between players.
- **FR-014**: Map-visibility and discovery MUST be independent: a player can discover (visit) a map-hidden room without affecting the room's map-hidden status, and a wizard can change a room's map-visibility without affecting any player's discovery state.

**Region transitions**

- **FR-015**: When the player moves through an exit whose destination room is in a different region, the map overlay MUST update so that (a) the region name in the header reflects the new region, and (b) the rendered rooms are the player's discovered rooms in the new region at the player's new elevation.

**Hover and interaction**

- **FR-016**: Hovering the pointer over any rendered room square MUST display the room's friendly name in a tooltip.
- **FR-017**: Hovering over a fog-of-war marker MUST NOT reveal the underlying destination room's name or any other identifying detail.
- **FR-018**: Clicking on a room square MUST NOT cause player movement — automated movement by map click is explicitly out of scope for this feature.

**Authoring and defaults**

- **FR-019**: New rooms MUST default to map-visible. Wizards MUST be able to toggle a room's map-visibility.
- **FR-020**: Every room MUST belong to exactly one Region (modeled as a first-class entity with its own id and friendly display name). The Room→Region relationship is a foreign-key reference.
- **FR-020a**: A single Region named **Blackmire** MUST exist as the canonical home for all seed/built-in content. All rooms created by seed scripts MUST reside in Blackmire.
- **FR-020b**: As part of this feature's deployment, all pre-existing rooms (and any state derived from them — exits, room-bound objects, NPC clones, etc.) MUST be purged. The seed flow MUST then create a fresh world consisting entirely of rooms that conform to the new schema (region=Blackmire, elevation=0, explicit `(x, y)` coordinates, map-visible by default). No backfill or coordinate-guessing logic is required.
- **FR-020c**: Seed scripts MUST author explicit `(x, y)` coordinates for every seed room so that the map overlay displays meaningful content on a fresh install, with no manual placement step required.
- **FR-021**: Every room MUST have an integer elevation value, defaulting to 0.
- **FR-022**: Room map coordinates MUST be optional metadata composed of two integers (x, y). A room with no coordinates set MUST be treated as off-map (FR-001/FR-003a). A room with coordinates (0, 0) MUST be treated as a normal on-map room at the (0, 0) position — (0, 0) is NOT a sentinel for "unset."
- **FR-022a**: A room's on-map position MUST be uniquely identified by the tuple `(region, elevation, x, y)`. The system MUST reject any attempt to create or update a room such that two rooms in the same region at the same elevation share the same `(x, y)`. The constraint applies only when coordinates are set (rooms with unset coordinates do not participate in uniqueness). Two rooms at DIFFERENT elevations within the same region MAY share `(x, y)` (multi-story stacking is supported).
- **FR-023**: Wizards MUST be able to set, change, and clear a room's map coordinates. Setting coordinates is independent of map-visibility (a wizard can mark a room map-visible without ever placing it, or place a room that is also map-hidden). Any coordinate change that would violate FR-022a or FR-024 MUST be rejected with a clear error.
- **FR-024**: Exit direction MUST be geometrically consistent with the source and target rooms' coordinates and elevation **when both rooms have coordinates set**. Specifically:
  - **North**: `target.y < source.y` AND `target.x == source.x` AND `target.elevation == source.elevation`.
  - **South**: `target.y > source.y` AND `target.x == source.x` AND `target.elevation == source.elevation`.
  - **East**: `target.x > source.x` AND `target.y == source.y` AND `target.elevation == source.elevation`.
  - **West**: `target.x < source.x` AND `target.y == source.y` AND `target.elevation == source.elevation`.
  - **Northeast**: `target.x - source.x == source.y - target.y > 0` AND `target.elevation == source.elevation`.
  - **Northwest**: `source.x - target.x == source.y - target.y > 0` AND `target.elevation == source.elevation`.
  - **Southeast**: `target.x - source.x == target.y - source.y > 0` AND `target.elevation == source.elevation`.
  - **Southwest**: `source.x - target.x == target.y - source.y > 0` AND `target.elevation == source.elevation`.
  - **Up**: `target.elevation > source.elevation` AND `target.x == source.x` AND `target.y == source.y`.
  - **Down**: `target.elevation < source.elevation` AND `target.x == source.x` AND `target.y == source.y`.
  - The distance along the direction (`|Δx|`, `|Δy|`, or `|Δelevation|` as applicable) may be any positive integer ≥ 1 — there is no maximum length. A single exit can therefore span multiple cells of the map plane (e.g., a long bridge or corridor).
  - If EITHER source OR target has unset coordinates (off-map), the geometric check is skipped — this is the supported pattern for wormhole/teleport-like exits (typically a vertical exit from an off-map room to a distant elevation).
  - The system MUST reject any exit create or edit that violates this rule.
- **FR-025**: The rendered length of an exit line on the map MUST be proportional to the distance between the two rooms it connects (in the exit's direction). A bridge spanning multiple cells displays as a visibly longer line than a one-cell adjacent connection.

### Key Entities *(include if feature involves data)*

- **Region**: A first-class entity (its own schema/table) representing a named map area containing one or more rooms. Has its own id and a friendly display name (e.g., "Blackmire") shown in the map header. Open to gaining region-level metadata later (description, theme, etc.) without affecting Room. Each room belongs to exactly one region via a foreign-key reference.
- **Room** *(extended)*: In addition to its existing identity and description, a room now holds a foreign-key reference to its Region (required), a map-visibility flag (default: visible), an elevation integer (default: 0), and OPTIONAL grid coordinates (x, y) within its region. A room with no coordinates set is off-map and does not render; coordinates of (0, 0) are a valid on-map position. Existing exits and behaviors are unaffected.
- **Exit** *(unchanged)*: Continues to be a directional connection from a source room to a target room in a named direction (one of the 8 compass directions, up, or down). The map renders pairs of exits between the same two rooms as a single undirected line, regardless of whether one or both exits exist.
- **PlayerDiscovery**: A per-player record of which rooms the player has personally entered. Used by the map to decide which rooms render as squares and which exit endpoints render as fog stubs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The current hardcoded map mockup (the static `map_nodes`/`map_edges` data backing the mini-map) is fully replaced — 0% of map rendering relies on hardcoded mock data after this feature lands.
- **SC-002**: When a player enters a previously-undiscovered map-visible room, the room appears on the player's map overlay within 1 second of the movement completing.
- **SC-003**: 0% of the map's rendered output reveals one-way exit directionality to any player — across all rendered lines, no visual cue distinguishes a one-way exit from a two-way exit.
- **SC-004**: 0% of map-hidden rooms (and 0% of the exits that lead to them) are rendered to any player on the map overlay, regardless of discovery state.
- **SC-005**: When a player moves through an exit that crosses regions, the map header's region name updates within 1 second, and only the new region's discovered rooms at the player's new elevation are rendered.
- **SC-006**: When a player ascends or descends, the map view filters to the new elevation within 1 second; 0% of rooms outside the new elevation are rendered as squares.
- **SC-007**: For 100% of rendered room squares, hovering reveals the room's friendly name via tooltip; for 100% of fog-of-war stubs, no underlying room name is revealed via tooltip or any other interaction.
- **SC-008**: The map UI surface contains 0 occurrences of a raw integer elevation value displayed to the player.
- **SC-009**: 100% of "discovered rooms above/below" affordances are present when at least one such room exists at a higher/lower elevation respectively, and absent when none exists.
- **SC-010**: When the player is in a map-hidden or unmapped (no-coordinates) room, the map drawing area renders 0 room squares, 0 fog stubs, and 0 "you are here" markers — only the region name header is shown.
- **SC-011**: A room with explicit coordinates (0, 0) renders on the map exactly as any other coordinate-bearing room — (0, 0) is never treated as "unset" by the renderer.
- **SC-012**: 100% of attempts to place two rooms at the same `(region, elevation, x, y)` are rejected by the system before the conflicting row is created or updated. 0% of map renders produce visually overlapping room squares within the same elevation slice.
- **SC-013**: 100% of exit create/edit attempts that violate FR-024 direction-consistency (e.g., a "north" exit whose target is geometrically south of the source, or a "up" exit at the same elevation as the source) are rejected with a clear, actionable error before the inconsistent exit can persist.
- **SC-014**: For any pair of connected rooms on the map, the rendered length of their connecting line is proportional to the geometric distance between their coordinate positions along the exit's direction — a one-cell exit is the shortest line on the map, a five-cell bridge is roughly five times that length.

## Assumptions

- **Discovery is per-player**: Each player accumulates their own discovery set. Two players in the same room may see different maps depending on where each has previously been. No shared/account-wide/party-wide discovery in v1.
- **Visiting a room marks it discovered regardless of map-visibility**: Walking into a map-hidden room still records discovery (so if a wizard later un-hides it, it appears as already-discovered). Map-hidden suppresses display, not knowledge.
- **The starting room is implicitly discovered**: A player has at least one discovered room from the moment they exist — the room they spawn into. No "empty map" state ever needs to render.
- **At most one exit per direction per source room**: Authoring is responsible for ensuring no two exits from the same source share the same direction. Multi-exit-per-direction is out of scope.
- **Direction and elevation are consistent**: An "up"/"down" exit is between rooms at different elevations; a compass-direction exit (N, NE, E, SE, S, SW, W, NW) is between rooms at the same elevation. This is an authoring constraint, not a runtime check this feature has to enforce.
- **Cardinal commands remain the sole movement mechanism**: Map clicks do nothing in this feature. All movement continues to happen via the existing command pipeline (north, east, up, etc.).
- **Exits between two rooms in different regions are legal**: A region is a map-rendering grouping, not a movement boundary. Cross-region exits behave like any other exit at the movement layer; they only differ visually on the map.
- **Hidden rooms remain fully reachable by cardinal command**: Setting a room map-hidden does not block movement — it only suppresses the visual representation. A player who knows the trick can still walk through a hidden door.
- **The existing 4-button dir pad (N/S/E/W) in the mockup is expected to grow** to support the full 8 compass directions plus up and down. The exact dir-pad layout is a UI concern of this feature.
- **Wizards author region membership, map-visibility, AND coordinates**: Region assignment for new rooms defaults to whatever a wizard sets at creation time; there is no auto-region-assignment heuristic. Coordinates are similarly explicit — there is no auto-placement based on exit topology. Unauthored coordinates remain unset, and the room stays off-map until the wizard places it.
- **Region inheritance for wizard-created rooms (forward-looking)**: When the wizard-room-creation feature lands later, a newly authored room will inherit its region from the wizard player's current room by default. This is not in scope for this feature (which has no wizard-creation flow yet) but the Region data model must support it cleanly.
- **Off-map rooms are still real rooms**: A room with no coordinates set is fully functional from a movement and game-logic standpoint — players can be in it, navigate exits, and discover it. It just never appears on the map, and standing in it gives the player a blank map (per FR-003a). This is a deliberate authoring tool for "instance" rooms, scratch rooms, or staging areas that shouldn't pollute any region's map.
- **No legacy world state to preserve**: This software has not yet been used by real users, so the migration path is a hard reset — pre-existing rooms (and dependent state: exits, room-bound objects, NPC clones, player rooms-occupied) are purged, and the seed flow rebuilds the world cleanly under the new schema. No backfill logic, no coordinate-guessing, no per-installation grandfather list.
- **Y-axis convention is screen coordinates**: This spec commits to the screen-coordinate convention — `y` increases downward, so a "north" exit goes to a smaller `y`. The convention is internal to the renderer; what matters for authoring is the consistent pairing of direction names to coordinate deltas codified in FR-024.
- **Long-distance exits may visually overlap intervening cells**: A bridge or long corridor exit (Δ > 1 along its axis) is rendered as a single long line on the map. If other rooms happen to occupy cells along that line, the line will visually overlap them. Wizards are responsible for arranging content so that these overlaps either don't occur or are visually acceptable (e.g., the bridge "passes over" a room at a different elevation, which is hidden by elevation filtering anyway).
- **Wormhole / teleport-like exits are simulated, not first-class**: There is no dedicated "wormhole" exit type. The pattern for now is: place a hub room off-map (no coordinates set, optionally map-hidden), and give it vertical or compass exits to rooms at distant elevations or coordinates that bypass the direction-consistency rule via FR-024's "skip check when either room is off-map" clause. The player passes through the off-map room momentarily (seeing a blank map) and emerges in the destination. This keeps the data model uniform — direction-consistency rules stay strict for mapped rooms.
- **The map renders a single elevation slice at a time**: There is no "expanded vertical view" affordance; the player's current elevation is the only one shown. Cross-elevation awareness comes from the above/below affordance only.
