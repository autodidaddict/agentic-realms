# Quickstart: Maps

Manual smoke test for the maps feature. Assumes a developer dev environment with PostgreSQL running and the asdf shims on PATH (see `MEMORY.md`).

## 1. Reset and re-seed

This is a **destructive** one-time operation per FR-020b. Pre-existing world state is purged; the seed re-authors everything under the new schema. Confirm the local DB has nothing you care about, then:

```sh
export PATH="/home/kevin/.asdf/shims:$PATH" && \
  mix do event_store.drop, event_store.create, event_store.init, \
         ecto.reset
```

`ecto.reset` runs `ecto.drop` + `ecto.create` + `ecto.migrate` + `run priv/repo/seeds.exs`. The four new migrations (reset, regions, room-extensions, player-discovered-rooms) run before the seed, and the seed creates Blackmire + Hollowvale + their rooms with explicit coordinates.

## 2. Start the server

```sh
export PATH="/home/kevin/.asdf/shims:$PATH" && mix phx.server
```

Open <http://localhost:4000> and sign in (or sign up — the existing auth flow is unchanged).

## 3. Verify the seeded world

The seed in `lib/agenticrealms/world/seed.ex` should create:

**Region**: `Blackmire`.

**Rooms in Blackmire (elevation 0)**:

```text
                map_x
        -1     0     1     2     3
       ┌─────┬─────┬─────┬─────┬─────┐
   -1  │     │ Cor │     │     │     │     map_y = -1
       ├─────┼─────┼─────┼─────┼─────┤
    0  │     │ Atr ├─────┤ Lib │     │     map_y = 0
       ├─────┼─────┼─────┼─────┼─────┤
    1  │     │     │     │     │ Brd │     map_y = 1 (cross-region exit)
       └─────┴─────┴─────┴─────┴─────┘
```

- `Atr` = **Stone Atrium** at `(0, 0, elevation=0)`. Has an Up exit to the Atrium Loft (elev=1). Has a North exit to North Corridor. Has an East exit to Dusty Library at distance 2 (a span — demonstrates the bridge/long-distance line).
- `Cor` = **North Corridor** at `(0, -1, 0)`. Has a South exit back to Atrium.
- `Lib` = **Dusty Library** at `(2, 0, 0)`. Has a West exit back to Atrium (long-distance return).
- `Brd` = **Blackmire Border** at `(3, 1, 0)`. Reached via a SE exit from the Atrium (distance 3 in NE-axis terms? — see Note 1). Cross-region exit leads east into Hollowvale.

> **Note 1 — bridge geometry**: For the demo to exercise the long-distance bridge rule (FR-024 + FR-025) along a diagonal, the Border must lie along a 45° axis from a room. The seed places the Border at `(3, 1, 0)` and the Atrium at `(0, 0, 0)` — these are NOT on a diagonal axis (Δx = 3, Δy = 1). The seed therefore connects Border via an additional small "Bridgehead" room at `(2, 0, 0)`, which IS east of Atrium at distance 2 (already used by Lib — see Note 2). Practically the seed will pick coordinates that make ONE of the demo exits a long-distance line (e.g., Atrium→Library at distance 2 east). The exact layout is finalized in tasks; the quickstart layout above is illustrative.

> **Note 2 — collision**: `(2, 0, 0)` cannot be occupied by both Lib and Bridgehead. The implementer adjusts the layout during task execution to avoid coordinate collisions while preserving the demo intent (bridge, fog stub, hidden room, cross-region, multi-floor).

**Rooms in Blackmire (elevation 1)**:

```text
            map_x = 0
       ┌─────┐
    0  │ Lft │     map_y = 0
       └─────┘
```

- `Lft` = **Atrium Loft** at `(0, 0, 1)`. Has a Down exit back to Atrium. No other exits at v1.

**Map-hidden room (Blackmire, elevation 0)**:

- `Vlt` = **Hidden Vault** at `(1, 0, 0)`, `map_visible: false`. Reached via a West exit from Library. The Vault never appears on the map, and Library's west-going exit line is suppressed entirely (FR-006).

**Cross-region room (Hollowvale)**:

- One room, e.g., **Hollowvale Outskirts**, with explicit coords at `(0, 0, 0)`. An East exit from Border to Outskirts demonstrates the cross-region affordance.

## 4. Acceptance walkthrough

Tick through US1–US7 by hand:

### US1 — Initial render

1. Sign in; you spawn into the Stone Atrium.
2. Click the map toggle (the map icon next to the input bar).
3. **Expected**: the map panel opens. Header reads "Region · Blackmire". Exactly one room glyph appears (Stone Atrium), highlighted with the player color. Up icon visible at the top-right corner of the glyph (because Atrium has an Up exit). The above-rooms affordance pip appears next to the region name (because the Loft exists at elev=1 and you'll discover it via the loft when you go up — but at this moment you haven't, so the pip is suppressed. The pip appears AFTER you discover the Loft.)

### US2 — Map updates on movement

1. Type `north` and submit.
2. **Expected**: the map updates. North Corridor appears as a new room glyph above the Atrium, the "you are here" highlight moves to the Corridor, and a connecting line is drawn vertically between Corridor and Atrium.
3. Type `south` to return.
4. **Expected**: highlight moves back to Atrium; Corridor remains as a discovered (non-current) room.

### US3 — One-way and fog-of-war information hiding

1. From Atrium, look around. Note: the seed includes a one-way exit from Library to Vault (or another deliberately one-way exit). Whichever pair: the line on the map looks identical to any other connecting line.
2. From Atrium, go `east`. Library appears via a long-distance line — visibly longer than the Atrium↔Corridor line. (Demonstrates FR-025.)
3. From Library, do NOT go through the west exit to the Vault yet (it's map-hidden — you wouldn't see it anyway).
4. Inspect the map: any exit toward an undiscovered visible room should appear as a fog stub. (If the seed lacks an undiscovered visible neighbor at this point, the implementer adds one — e.g., a "Cellar" beyond the Library with a south exit, undiscovered at this stage.)
5. Hover over the fog stub. **Expected**: no tooltip, no name reveal.

### US4 — Vertical exits and elevation filtering

1. From Atrium, type `up`.
2. **Expected**: the map header still reads "Region · Blackmire". The Atrium and Corridor disappear; the Loft appears, highlighted, with a Down icon at the bottom-right corner. The below-rooms affordance pip is visible (because you have discovered rooms at elev=0).
3. Type `down`. Back at Atrium. Up icon visible on Atrium; above-rooms affordance pip is now visible.

### US5 — Hidden room

1. From the Atrium, go `east` to the Library.
2. Inspect the west side of the Library on the map. **Expected**: there is no west-going line or fog stub from the Library. The Library glyph looks identical to a room with no west exit.
3. Type `west`. You arrive in the Hidden Vault. **Expected**: the map header still reads "Region · Blackmire" but the canvas is blank (FR-003a) — the Vault is hidden. No "you are here" marker, no Atrium/Library/Corridor glyphs.
4. Type `east` to return to the Library. The full map of discovered Blackmire rooms reappears.

### US6 — Cross-region transition

1. From the Atrium, walk to the Blackmire Border (via the seeded path).
2. Inspect the east side of the Border. **Expected**: a dashed line (cross-region affordance) extending east, terminating in a small portal glyph. The destination room is NOT rendered on this view.
3. Type `east`. You arrive in Hollowvale Outskirts.
4. **Expected**: the map header now reads "Region · Hollowvale". Only Hollowvale rooms appear (just Outskirts in v1). The cross-region affordance now points back west (where Blackmire was), not east.

### US7 — Hover tooltip

1. Open the map. Hover over any rendered room glyph.
2. **Expected**: tooltip appears (CSS-styled). Contains the room's display name (e.g., "Stone Atrium"). Disappears when the mouse leaves the glyph.
3. Hover over a fog stub (if you've left an undiscovered exit in view).
4. **Expected**: NO tooltip appears.

## 5. Devtools sanity checks

In Chrome / Firefox devtools, inspect the rendered DOM. Verify:

- The map's `<svg>` element contains:
  - `<title>` children inside each `.map-cell` group.
  - NO `<title>` inside any `.map-fog-stub` or `.map-portal`.
  - NO digit sequences in any `data-*` attribute that could be a leaked elevation.
- The map header contains the region name; no integer beside it.
- The dir-pad has all 8 cardinal buttons (NE, NW, SE, SW visible in the corners of a 3×3 grid) plus a paired Up/Down column.

## 6. Tests

```sh
export PATH="/home/kevin/.asdf/shims:$PATH" && \
  mix test test/agenticrealms/world/direction_test.exs \
            test/agenticrealms/world/direction/geometry_test.exs \
            test/agenticrealms/world/exits/validator_test.exs \
            test/agenticrealms/world/map_view_test.exs \
            test/agenticrealms/world/region_test.exs \
            test/agenticrealms/world/projections/world_projector_region_test.exs \
            test/agenticrealms/world/projections/world_projector_room_extensions_test.exs \
            test/agenticrealms_web/components/game_components_mini_map_test.exs
```

And the integration test (longer, hits the DB and LiveView):

```sh
export PATH="/home/kevin/.asdf/shims:$PATH" && \
  mix test --only integration test/agenticrealms_web/live/game_live_maps_test.exs
```

## 7. Troubleshooting

| Symptom                                                                                | Likely cause                                                                                 |
|----------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `ecto.reset` fails complaining about FK violations                                     | Forgot to run `event_store.drop` first; old events reproject into the new schema.            |
| Map renders blank even though you can see rooms in the log                             | Player's `current_room_id` was nulled (FR-022) — re-spawn by signing out + back in.          |
| Diagonals look "stepped" or pixelated                                                  | SVG `<line>` got `stroke-linejoin: miter`; should be `round`. Check CSS.                    |
| Fog stub reveals a room name on hover                                                  | Bug — investigate `mini_map/1`. The renderer must NOT emit `<title>` on fog stubs (FR-017). |
| "Region · " header shows no name                                                       | Player is in a room whose `region_id` doesn't resolve. Check seed; check `regions` table.    |
| Crossing into Hollowvale doesn't swap the map                                          | `MapView.for_player/1` not re-computed on `PlayerCurrentRoomChanged`. Check `GameLive`.      |
| Up icon appears on a room with no Up exit                                              | `MapView.Room.has_up?` computed wrong — check the exits-to-room association for that room.   |
| Two glyphs render at the same coordinate                                               | Partial unique index missing or migration failed silently. Check `world_rooms_unique_position`. |
