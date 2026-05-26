# Contract: World.MapView

## Module: `AgenticRealms.World.MapView`

A pure read-model query module. Given a player id, returns a `%MapView{}` struct describing exactly what should appear on the map overlay for that player at this moment.

### Top-level function

```elixir
@spec for_player(player_id :: pos_integer()) :: %MapView{}

def for_player(player_id) do
  with {:ok, current_room} <- fetch_current_room(player_id) do
    if off_map?(current_room) do
      build_off_map_view(current_room)
    else
      build_normal_view(player_id, current_room)
    end
  else
    # Player has no current room (FR-022 edge: nullified) — show no map.
    {:error, :no_current_room} -> empty_view()
  end
end
```

### `off_map?/1`

```elixir
defp off_map?(%Room{map_visible: false}), do: true
defp off_map?(%Room{map_x: nil}), do: true
defp off_map?(%Room{map_y: nil}), do: true
defp off_map?(_), do: false
```

### `build_off_map_view/1` (FR-003a)

```elixir
defp build_off_map_view(%Room{region_id: region_id} = current) do
  region = Repo.get!(Region, region_id)

  %MapView{
    region_id: region.id,
    region_name: region.name,
    current_room_id: current.id,
    off_map?: true,
    viewport_center: {0, 0},
    rooms: [],
    exits: [],
    has_above_rooms?: false,
    has_below_rooms?: false
  }
end
```

### `build_normal_view/2`

Pseudocode:

```text
1. region = fetch region for current_room.region_id
2. discovered_ids = SELECT room_id FROM player_discovered_rooms WHERE player_id = ?
3. viewport = window of (current.map_x ± W/2, current.map_y ± W/2) where W = configured viewport_cells
4. candidate_rooms = SELECT * FROM world_rooms
                       WHERE region_id = current.region_id
                         AND elevation = current.elevation
                         AND map_visible = true
                         AND map_x BETWEEN viewport.min_x AND viewport.max_x
                         AND map_y BETWEEN viewport.min_y AND viewport.max_y
                         AND id IN discovered_ids
5. candidate_room_ids = MapSet of candidate_rooms ids
6. all_exits_from_candidates = SELECT * FROM world_exits WHERE source_room_id IN candidate_room_ids
7. For each exit, classify:
   - target_room = lookup in world_rooms (joined or fetched)
   - if target_room is nil OR not map_visible OR coords are nil → SUPPRESS (FR-006)
   - if target_room.region_id != current.region_id → :cross_region (FR-008)
   - if target_room.id NOT IN discovered_ids → :fog_stub (FR-007)
   - if target_room.id IN discovered_ids AND IN candidate_room_ids → :normal
   - else (target discovered but outside viewport) → SUPPRESS (off-screen)
8. Deduplicate normal exits by unordered (source_id, target_id) pair (FR-004)
9. For each candidate room, compute has_up? and has_down? by checking
   if the room has an Up / Down exit (to a visible, coord-bearing target). Hidden-target
   exits do NOT trigger the icon (FR-006 also suppresses the icon).
10. has_above_rooms? / has_below_rooms? = EXISTS query against world_rooms
    JOIN player_discovered_rooms for the same region with elevation > / < current.elevation.
11. Map candidate_rooms → MapView.Room structs (no internal room ids leaked to fog stubs).
12. Map exits → MapView.Exit structs with computed line endpoints.
13. Build the %MapView{}.
```

### `empty_view/0`

Used when the player has no current room (post-FR-022 nullification or pre-spawn). Renders a region-less, header-less blank.

```elixir
defp empty_view do
  %MapView{
    region_id: nil,
    region_name: nil,
    current_room_id: nil,
    off_map?: true,
    viewport_center: {0, 0},
    rooms: [],
    exits: [],
    has_above_rooms?: false,
    has_below_rooms?: false
  }
end
```

### Query module additions

The MapView delegates to `AgenticRealms.World.Queries` for the heavy lifting:

```elixir
@spec discovered_room_ids_for(player_id :: pos_integer()) :: MapSet.t()
@spec rooms_in_region_at_elevation_within_viewport(
        region_id :: binary_id,
        elevation :: integer,
        center :: {integer, integer},
        viewport_cells :: pos_integer()
      ) :: [%Room{}]
@spec exits_from_rooms(room_ids :: [binary_id]) :: [%Exit{}]
@spec has_discovered_rooms_at_elevations?(
        region_id :: binary_id,
        elevations :: [integer],
        player_id :: pos_integer()
      ) :: boolean
```

The viewport-bounded `rooms_in_region_at_elevation_within_viewport/4` ensures the per-render work is `O(viewport_cells²)` worst case, regardless of how large the region is.

### Information-hiding contract

**MUST**:
- Suppress hidden-target exits entirely (no line, no stub, no affordance).
- Suppress target room identity on fog stubs (no name in struct, no DOM-derivable id in the renderer).
- Suppress one-way direction information (the renderer draws each connection once per unordered room pair; the validator-on-build ensures no asymmetric rendering).

**MUST NOT**:
- Include the destination room id in a `MapView.Exit{kind: :fog_stub}` entry.
- Include the destination region name in a `MapView.Exit{kind: :cross_region}` entry.
- Include the raw elevation integer as a struct field for the renderer (only `has_above_rooms?` / `has_below_rooms?` booleans).

### Performance

- `for_player/1` is dominated by three SQL queries:
  1. `SELECT room_id FROM player_discovered_rooms WHERE player_id = ?` — single index scan.
  2. The bounded viewport room query — single index range scan on `(region_id, elevation, map_x)`.
  3. The exits-from-rooms query — index scan on `(source_room_id)`.
- Plus two `EXISTS` queries for `has_above_rooms?` / `has_below_rooms?`.
- All five are sub-millisecond for realistic data shapes. The renderer adds another sub-millisecond of struct building. Total budget: < 5 ms server-side per re-render.
