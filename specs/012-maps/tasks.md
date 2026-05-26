# Tasks: Maps (Feature 012)

**Input**: Design documents from `/specs/012-maps/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Test tasks are INCLUDED — every prior feature (008–011) shipped with paired test coverage and the spec defines 14 measurable success criteria. The pattern continues.

**Organization**: Tasks are grouped by user story (US1–US7 from spec.md) so each story can be implemented and verified after the foundational layer is complete. Within stories, tests are co-located with the implementation they verify.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable — different files, no dependency on incomplete tasks.
- **[Story]**: US1–US7; omitted for Setup, Foundational, and Polish phases.

## Path Conventions

Phoenix LiveView single project. All paths under repo root. Implementation under `lib/`, tests under `test/`. The repo is also accessible via the symlink at `/home/kevin/code/autodidaddict/agentic-realms/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project-level config + directory scaffolding.

- [X] T001 [P] Create directory `lib/agenticrealms/world/direction/` for the new `Geometry` module.
- [X] T002 [P] Create directory `lib/agenticrealms/world/exits/` for the new `Validator` module.
- [X] T003 [P] Create directory `test/agenticrealms/world/direction/` for `geometry_test.exs`.
- [X] T004 [P] Create directory `test/agenticrealms/world/exits/` for `validator_test.exs`.
- [X] T005 [P] Create directory `test/agenticrealms_web/components/` if it does not yet exist (for `game_components_mini_map_test.exs`).
- [X] T006 [P] In `config/config.exs`, add `config :agenticrealms, AgenticRealms.MapRenderer, cell_size_px: 56, viewport_cells: 11, node_padding_px: 4` with a brief comment naming each value's purpose. `viewport_cells` must be odd so a center cell exists.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Direction / Geometry / Validator pure modules, the new Region aggregate, the Room aggregate's schema/command/event extensions, the Player aggregate's discovery extension, the migration chain, and the seed rewrite. Aggregates and pure modules are clearly distinguished in each section heading below. Every task in this phase MUST complete before any user-story phase begins.

**⚠️ CRITICAL**: No US1–US7 work can begin until this phase is complete.

### Direction module extension

- [X] T007 In `lib/agenticrealms/world/direction.ex`, extend `@canonical` to include `:northeast`, `:northwest`, `:southeast`, `:southwest`. Add `parse/1` aliases for `"northeast"`, `"ne"`, `"northwest"`, `"nw"`, `"southeast"`, `"se"`, `"southwest"`, `"sw"`. Extend `opposite/1` with NE↔SW and NW↔SE clauses. Extend `to_string/1` with the four new cases (both atom→string and string-passthrough clauses). See `contracts/direction.md`.
- [X] T008 [P] Extend `test/agenticrealms/world/direction_test.exs` with tests for the four new diagonals: `parse/1` of canonical strings + aliases, `opposite/1` round-trips, `to_string/1` for both atom and string inputs. Confirm existing assertions for N/S/E/W/Up/Down still pass.

### Direction.Geometry module (new — pure module, no aggregate)

- [X] T009 Create `lib/agenticrealms/world/direction/geometry.ex` per `contracts/direction.md`: implement `delta/1` (all 10 directions, screen-coord convention with `y` increasing downward), `consistent?/3` (FR-024 strict-axis + flexible distance + off-map skip), `unit_vector/1` (all 8 planar directions; raises for `:up`/`:down`). Document the y-axis convention in the moduledoc.
- [X] T010 [P] Create `test/agenticrealms/world/direction/geometry_test.exs` per `contracts/direction.md` test surface: `delta/1` matrix for all 10 directions; `consistent?/3` accept matrix (cardinal/diagonal/vertical, distance 1 and ≥ 2, both rooms on-map); `consistent?/3` reject matrix (off-axis, wrong sign, elevation mismatch for planar, horizontal offset for vertical, zero elevation change); `consistent?/3` off-map skip (source off-map, target off-map, both off-map). `unit_vector/1` returns expected components for all 8 planar directions.

### Exits.Validator module (new — pure module, no aggregate)

- [X] T011 Create `lib/agenticrealms/world/exits/validator.ex` per `contracts/exit-validator.md`: single function `consistent?/3` that delegates to `Direction.Geometry.consistent?/3` and wraps `{:error, reason}` into `{:error, {:exit_geometry_violation, reason}}`.
- [X] T012 [P] Create `test/agenticrealms/world/exits/validator_test.exs` with the full accept/reject matrix per `contracts/exit-validator.md`. Uses ExUnit `for` comprehensions over directions × source/target shapes × distances to generate ~40 cases. Each rejection asserts the specific `:reason` atom.

### Region aggregate (new, event-sourced)

- [X] T013 Create `lib/agenticrealms/world/schemas/region.ex` Ecto schema per `data-model.md §1.1`: `@primary_key {:id, :binary_id, autogenerate: false}`, schema `regions`, fields `name :string`, timestamps. Add `has_many :rooms, AgenticRealms.World.Schemas.Room, foreign_key: :region_id`.
- [X] T014 [P] Create `lib/agenticrealms/world/commands/create_region.ex` per `contracts/region.md`: `@enforce_keys [:region_id, :name]`, defstruct `[:region_id, :name]`.
- [X] T015 [P] Create `lib/agenticrealms/world/events/region_created.ex` per `contracts/region.md`: `@derive Jason.Encoder`, `@enforce_keys [:region_id, :name]`, defstruct `[:region_id, :name, version: 1]`.
- [X] T016 Create `lib/agenticrealms/world/region.ex` aggregate per `contracts/region.md`: `defstruct id: nil, name: nil`. `execute/2` for `%CreateRegion{}` with `id: nil` returns `%RegionCreated{}`; with `id: _` returns `{:error, :region_already_exists}`. Add a name-validation guard (trim + non-empty). `apply/2` for `%RegionCreated{}` populates the state.
- [X] T017 Update `lib/agenticrealms/world/application.ex` (the Commanded application's router config) to identify `AgenticRealms.World.Region` by `:region_id` and dispatch `CreateRegion` to it.
- [X] T018 In `lib/agenticrealms/world/commands.ex`, add a `create_region/2` wrapper that (a) checks the read model for an existing region with the same `name`, returning `{:error, :region_name_taken}` if present, (b) dispatches `%CreateRegion{}` with `consistency: :strong`.
- [X] T019 [P] Extend `lib/agenticrealms/world/projections/world_projector.ex` `handle/2` with a clause for `%RegionCreated{region_id: id, name: name}` that inserts a `%Region{id: id, name: name}` row with `on_conflict: :nothing, conflict_target: :id`.
- [X] T020 [P] Create `test/agenticrealms/world/region_test.exs`: `execute/2` happy path emits `%RegionCreated{}`; `execute/2` on already-created aggregate returns `{:error, :region_already_exists}`; `apply/2` round-trip restores state from the event.
- [X] T021 [P] Create `test/agenticrealms/world/projections/world_projector_region_test.exs`: emit `%RegionCreated{}`, assert the `regions` row is present; replay the event a second time and assert no duplicate (`on_conflict: :nothing`).

### Room aggregate + schema + command + event extensions (existing aggregate, extended)

- [X] T022 In `lib/agenticrealms/world/schemas/room.ex`, add the new fields: `field :region_id, :binary_id`, `field :map_visible, :boolean, default: true`, `field :elevation, :integer, default: 0`, `field :map_x, :integer`, `field :map_y, :integer`. Add `belongs_to :region, AgenticRealms.World.Schemas.Region, foreign_key: :region_id, define_field: false`. (The schema's `define_field: false` ensures the existing `field :region_id` is the FK column without Ecto trying to create a second one.)
- [X] T023 [P] In `lib/agenticrealms/world/commands/create_room.ex`, add `:region_id` to `@enforce_keys`. Extend defstruct with `region_id: nil, map_visible: true, elevation: 0, map_x: nil, map_y: nil`.
- [X] T024 [P] In `lib/agenticrealms/world/events/room_created.ex`, add `:region_id` to `@enforce_keys`. Extend defstruct with `region_id: nil, map_visible: true, elevation: 0, map_x: nil, map_y: nil` (bumped after `behaviors: []`, keeping `version: 1`).
- [X] T025 In `lib/agenticrealms/world/room.ex`, extend `execute/2` for `%CreateRoom{}` to carry all new fields through to `%RoomCreated{}`. Extend the apply clause for `%RoomCreated{}` to populate the new fields on aggregate state. Add the new fields to the aggregate's `defstruct` so the in-memory shape includes `region_id`, `map_visible`, `elevation`, `map_x`, `map_y` (defaults match the event).
- [X] T026 In `lib/agenticrealms/world/commands.ex`, extend `create_room/*` wrappers to accept and validate the new fields: (a) region exists in the read model; (b) coordinates are both nil or both non-nil integers (`{:error, :coords_must_be_pair}` on mixed); (c) if coords set, no existing row at `(region_id, elevation, map_x, map_y)` (`{:error, :coord_taken}`); (d) elevation is an integer. Validation order: region first, coord pair shape next, then uniqueness, then elevation type. Dispatch `%CreateRoom{}` only after all checks pass.
- [X] T027 Extend `lib/agenticrealms/world/projections/world_projector.ex` `handle/2` clause for `%RoomCreated{}` to include the new fields in the `Repo.insert!/2` keyword list: `region_id, map_visible, elevation, map_x, map_y`.
- [X] T028 [P] Create `test/agenticrealms/world/projections/world_projector_room_extensions_test.exs`: emit `%RoomCreated{}` with non-nil coords, assert the row is inserted with all five new fields correctly typed; emit one with `map_x: nil, map_y: nil`, assert nulls round-trip; replay both events and assert idempotency.

### AddExit validator integration (wires the Exits.Validator module into the Commands wrapper)

- [X] T029 In `lib/agenticrealms/world/commands.ex`, update `add_exit/3` to: (1) fetch the source room from the read model (`Queries.get_room/1` or equivalent — promote a helper if needed), (2) fetch the target room, (3) call `AgenticRealms.World.Exits.Validator.consistent?/3` with `(direction, source, target)`, (4) only on `:ok` dispatch `%AddExit{}`. Return `{:error, :room_not_found}` if either fetch fails; return the validator's error tuple unchanged on geometric violation.

### Migrations (must run in order; pair with `event_store.drop` per quickstart.md §1)

- [X] T030 Create `priv/repo/migrations/<ts1>_reset_world_for_maps.exs` per `data-model.md §5.1`: TRUNCATE `world_rooms`, `world_exits`, `world_objects`, `npc_clones`, `npc_blueprints` RESTART IDENTITY CASCADE; `UPDATE player_state SET current_room_id = NULL`. Down migration is a no-op (`def down, do: :ok`). Use the next available `YYYYMMDDHHMMSS` timestamp.
- [X] T031 Create `priv/repo/migrations/<ts2>_create_regions.exs` per `data-model.md §1.1`: `create table(:regions, primary_key: false) do add :id, :binary_id, primary_key: true; add :name, :string, null: false; timestamps(type: :utc_datetime); end; create unique_index(:regions, [:name])`. Use the next available timestamp after T030.
- [X] T032 Create `priv/repo/migrations/<ts3>_extend_world_rooms_with_map_fields.exs`: `alter table(:world_rooms) do add :region_id, references(:regions, type: :binary_id, on_delete: :restrict), null: false; add :map_visible, :boolean, null: false, default: true; add :elevation, :integer, null: false, default: 0; add :map_x, :integer; add :map_y, :integer; end`. Then `create unique_index(:world_rooms, [:region_id, :elevation, :map_x, :map_y], where: "map_x IS NOT NULL AND map_y IS NOT NULL", name: :world_rooms_unique_position)` and `create index(:world_rooms, [:region_id, :elevation])`. Use the next available timestamp after T031.
- [X] T033 Create `priv/repo/migrations/<ts4>_create_player_discovered_rooms.exs` per `data-model.md §1.4`: `create table(:player_discovered_rooms, primary_key: false) do add :player_id, references(:players, on_delete: :delete_all), primary_key: true; add :room_id, references(:world_rooms, type: :binary_id, on_delete: :delete_all), primary_key: true; add :discovered_at, :utc_datetime, null: false; end`. Use the next available timestamp after T032.
- [X] T034 Run the migration chain locally to confirm it applies cleanly: `export PATH="/home/kevin/.asdf/shims:$PATH" && mix do event_store.drop, event_store.create, event_store.init, ecto.reset` and assert it completes without errors. Re-run `mix ecto.migrate` to confirm no pending changes remain. (This task verifies the migration chain; it does NOT seed yet — seed is T046.)

### Player aggregate extension — discovery (existing World.Player aggregate, extended with discovered_room_ids + RecordRoomDiscovery + PlayerDiscoveredRoom)

- [X] T035 [P] Create `lib/agenticrealms/world/schemas/player_discovered_room.ex` Ecto schema per `data-model.md §1.4`: `@primary_key false`, schema `player_discovered_rooms`, fields `player_id :id primary_key: true`, `room_id :binary_id primary_key: true`, `discovered_at :utc_datetime`.
- [X] T036 [P] Create `lib/agenticrealms/world/events/player_discovered_room.ex` per `contracts/discovery.md`: `@derive Jason.Encoder`, `@enforce_keys [:player_id, :room_id, :discovered_at]`, defstruct `[:player_id, :room_id, :discovered_at, version: 1]`.
- [X] T037 [P] Create `lib/agenticrealms/world/commands/record_room_discovery.ex` per `contracts/discovery.md`: `@enforce_keys [:player_id, :room_id]`, defstruct `[:player_id, :room_id]`.
- [X] T038 In `lib/agenticrealms/world/player.ex`, extend the aggregate per `contracts/discovery.md`: add `discovered_room_ids: MapSet.new()` to the defstruct (after the existing `current_room_id: nil` field); add `execute/2` clause for `%RecordRoomDiscovery{}` that returns `:ok` when the room is already in the MapSet OR `%PlayerDiscoveredRoom{...}` when it isn't (timestamp via `DateTime.utc_now() |> DateTime.truncate(:second)`); add `apply/2` clause for `%PlayerDiscoveredRoom{}` that `MapSet.put`s the room id. The aggregate `id` is populated by the existing `PlayerSpawned` apply clause; no change needed there.
- [X] T039 Update `lib/agenticrealms/world/application.ex` router config to dispatch `RecordRoomDiscovery` to `AgenticRealms.World.Player`. The aggregate is already identified by `:player_id` from feature 003.
- [X] T040 In `lib/agenticrealms/world/commands.ex`, add a `record_room_discovery/2` wrapper: dispatches `%RecordRoomDiscovery{player_id: pid, room_id: rid}` with `consistency: :strong`.
- [X] T041 Extend `lib/agenticrealms/world/projections/world_projector.ex` `handle/2` with a clause for `%PlayerDiscoveredRoom{}` that inserts a `%PlayerDiscoveredRoom{}` schema row with `on_conflict: :nothing, conflict_target: [:player_id, :room_id]`.
- [X] T042 Extend `lib/agenticrealms/world/projections/player_state_projector.ex`: in `handle/2` for `%PlayerSpawned{}` AND `%PlayerMoved{}`, after the existing `current_room_id` update, unconditionally dispatch `AgenticRealms.World.Commands.record_room_discovery(player_id, target_room_id)`. For `PlayerMoved`, only dispatch if `room_exists?(to)` returns true (preserves the existing FR-022 guard). The projector NEVER consults `player_discovered_rooms` directly; idempotency is the aggregate's responsibility per `contracts/discovery.md`.
- [X] T043 [P] Extend `test/agenticrealms/world/player_test.exs` with: first `RecordRoomDiscovery` on a fresh aggregate emits `%PlayerDiscoveredRoom{}`; second `RecordRoomDiscovery` with the same room emits no event (returns `:ok` with no event); `apply/2` of `%PlayerDiscoveredRoom{}` adds the room to `discovered_room_ids`; rehydration from a stream of `[PlayerSpawned, PlayerDiscoveredRoom(A), PlayerDiscoveredRoom(B)]` yields an aggregate whose MapSet contains both `A` and `B`.
- [X] T044 [P] Create `test/agenticrealms/world/projections/world_projector_discovery_test.exs`: emit `%PlayerDiscoveredRoom{}` twice with the same `(player_id, room_id)`, assert exactly one row in `player_discovered_rooms`; per-player isolation (two players, same room → two rows).

### Seed rewrite

- [X] T045 Rewrite `lib/agenticrealms/world/seed.ex` per `quickstart.md §3`. The new flow:
  1. Read constants for region ids (`@blackmire_region_id`, `@hollowvale_region_id`) and room ids (Stone Atrium, North Corridor, Dusty Library, Atrium Loft, Hidden Vault, Blackmire Border, Hollowvale Outskirts — all UUIDs).
  2. Create the Blackmire region via `Commands.create_region/2`.
  3. Create the Hollowvale region.
  4. Re-create every room with explicit `region_id`, `elevation`, `map_x`, `map_y`, `map_visible`. Use a layout that exercises: (a) at least one long-distance bridge (Δ ≥ 2 along an axis between two seeded rooms — e.g., Atrium↔Library at distance 2 east), (b) at least one Up/Down pair (Atrium↔Atrium Loft, elev 0 ↔ elev 1, same `(map_x, map_y)`), (c) one map_visible:false room reachable from a visible room (Hidden Vault west of Library), (d) one cross-region exit (Border in Blackmire east to Outskirts in Hollowvale), (e) at least one undiscovered visible neighbor at first spawn to demonstrate fog stubs on US3 (e.g., a "Cellar" south of Library, undiscovered at spawn).
  5. Re-add all paired exits (north↔south, east↔west, up↔down) using `Commands.add_exit/3`. The validator must accept every authored exit per FR-024; if it rejects any, the seed fails loudly.
  6. Re-add the existing objects (brass lantern, leather journal, reading lectern) into rooms that exist in the new layout.
  7. Re-create the Garrick blueprint + clone in the Stone Atrium.
  8. The existing `behaviors` and `lore` payloads carry over unchanged.

  Preserve the existing `@starting_room_id` so `Seed.starting_room_id/0` continues returning the Atrium's UUID and existing `Commands.spawn/2` calls work. Update `@starting_room_id`'s value only if the Atrium's UUID needs to change for layout reasons (avoid if possible — minimizes test churn).
- [X] T046 Run `mix ecto.reset` to verify the new seed runs end-to-end against the post-migration schema. Confirm: regions row count == 2 (Blackmire + Hollowvale), world_rooms row count == 7 (per layout in T045), world_exits row count matches the paired-exit count.
- [X] T047 Extend (or create) `test/agenticrealms/world/seed_test.exs` to assert: Blackmire and Hollowvale regions exist; Stone Atrium is in Blackmire at `(map_x=0, map_y=0, elevation=0)`; Atrium Loft is in Blackmire at the SAME `(map_x, map_y)` but elevation=1; Hidden Vault has `map_visible: false`; the cross-region exit from Blackmire Border to Hollowvale Outskirts exists; at least one paired exit spans Δ ≥ 2 cells.

**Checkpoint**: Foundation ready. Pure modules (Direction, Direction.Geometry, Exits.Validator, plus the MapView module added in US1) are stateless helpers. Aggregates in place: Region (new), Room (extended with map fields), Player (extended with discovery). Migrations applied; seed rewritten. The world boots and the player spawns into the Stone Atrium with the Atrium recorded in `player_discovered_rooms` via the event-sourced path. User story implementation can now begin.

---

## Phase 3: User Story 1 — Real region map replaces the mockup (Priority: P1) 🎯 MVP

**Goal**: A player opens the map overlay and sees their current region's discovered rooms drawn on a 2D plane, with the current room visibly highlighted and the region name in the header.

**Independent test**: A freshly seeded player who has only stood in the Stone Atrium opens the map overlay and sees exactly one room glyph (the Atrium), highlighted as current, with header "Region · Blackmire".

### MapView read model (basic — current region, current elevation, discovered, exit lines)

- [X] T048 [P] [US1] Add `discovered_room_ids_for/1` to `lib/agenticrealms/world/queries.ex`: returns a `MapSet` of room ids the given player has discovered. Single SQL query against `player_discovered_rooms`.
- [X] T049 [P] [US1] Add `rooms_in_region_at_elevation_within_viewport/4` to `lib/agenticrealms/world/queries.ex` per `contracts/map-view.md`: filter `world_rooms` by region_id + elevation + map_visible + coord-non-null + coord-within-viewport-window + id-in-discovered. Returns a list of `%Room{}` rows.
- [X] T050 [P] [US1] Add `exits_from_rooms/1` to `lib/agenticrealms/world/queries.ex`: given a list of source room ids, returns all `%Exit{}` rows whose `source_room_id` is in the list (with the target room preloaded for the renderer's classification step).
- [X] T051 [US1] Create `lib/agenticrealms/world/map_view.ex` per `contracts/map-view.md`. Implement `for_player/1` plus the helper `build_normal_view/2`, `off_map?/1`, `empty_view/0`. For US1 the normal-view build only needs to emit `:normal` exit kinds (between two rendered rooms) — `:fog_stub` and `:cross_region` are added in US3 (T060) and US6 (T071). Implement room-pair deduplication for `:normal` exits.
- [X] T052 [US1] Define `lib/agenticrealms/world/map_view.ex` nested structs `MapView.Room` and `MapView.Exit` per `data-model.md §2.2`/`§2.3`.
- [X] T053 [P] [US1] Create `test/agenticrealms/world/map_view_test.exs` with US1 cases per `research.md R10` fixtures:
  - `single_room/0`: returns one `MapView.Room`, `is_current?: true`, region_name correct, no exits, no above/below.
  - `linear_three/0`: returns three rooms, two normal exits (dedup verified — no four-entry list from reciprocal pairs), the middle room flagged current.
  - Off-map: a player whose current room has `map_x: nil` returns `off_map?: true`, `rooms: []`, `exits: []` per FR-003a.
  - Region header correctness across all fixtures.

### mini_map/1 component rewrite (basic SVG)

- [X] T054 [US1] In `lib/agenticrealms_web/components/game_components.ex`, REPLACE the `mini_map/0` (or `/1`, depending on current arity) function with the SVG-primary renderer per `contracts/mini-map-component.md`. For US1, render:
  - The `.map-panel` outer div.
  - The `.map-header` with `<h4>` showing `@map_view.region_name`.
  - The `<svg class="map-canvas">` with `viewBox` computed from the player-centered viewport.
  - One `<g class="map-cell">` per `@map_view.rooms` entry, containing a `<title>` (room name) and a `<rect class="map-rect">`. The current room gets the `map-cell--current` class.
  - One `<line class="map-line">` per `@map_view.exits` entry (only `:normal` kind in this phase).
  - The off-map branch (`@map_view.off_map?`) renders only the header + an empty `.map-canvas--off-map` div.

  The component takes a single required `attr :map_view, MapView`. Drop the `GameData.map_nodes/0` and `GameData.map_edges/0` calls.
- [X] T055 [US1] In `lib/agenticrealms_web/live/game_live.ex`, in `mount/3`: after computing `current_room_id`, also compute `map_view = AgenticRealms.World.MapView.for_player(player_id)` and assign it to the socket. Add a `handle_info/2` clause for `%PlayerCurrentRoomChanged{}` that recomputes `map_view` and re-assigns it. (Other re-render triggers — region transitions, elevation changes — are handled by the same handler because they all involve a `current_room_id` change.) Remove any remaining references to `GameData.map_nodes/0` / `GameData.map_edges/0`.
- [X] T056 [US1] In `lib/agenticrealms_web/components/game_components.ex`, update the `player_view/1` callsite to pass `map_view={@map_view}` into `<.mini_map />`. Update the `<.mini_map>` attr declaration to accept and require `:map_view`.

### CSS for basic map (replaces the mockup styles)

- [X] T057 [US1] In `assets/css/game.css`, REPLACE the `.map`, `.map-grid`, `.map-node`, `.map-node.current`, `.map-node.visited`, `.map-edge` rules (around lines 1455–1491) with new SVG-targeting rules per `contracts/mini-map-component.md`:
  - `.map-canvas` — SVG container; fixed width/height from `viewport_cells × cell_size_px`; centered in the panel.
  - `.map-canvas--off-map` — blank canvas for off-map state.
  - `.map-cell` — group container (`color: var(--ink-dim)`).
  - `.map-cell--current` — bright fill on `.map-rect`, soft outer glow via `filter: drop-shadow(0 0 12px var(--player))`.
  - `.map-cell:hover` — stroke `var(--player)`.
  - `.map-rect` — fill `var(--bg-inset)`, stroke `var(--ink-dim)`, stroke-width 1.5, `rx="4"`.
  - `.map-line` — stroke `var(--ink-dim)`, stroke-width 2, no dash. `stroke-linecap: round`.
  - `.map-header` — flex row, region name typography matches the existing stat-block `<h4>`.

  Preserve existing `.dir-pad` styles for now (expanded in Polish).

### Component snapshot test (US1 fixtures)

- [X] T058 [P] [US1] Create `test/agenticrealms_web/components/game_components_mini_map_test.exs`. Use `Phoenix.LiveViewTest.render_component/3` (or `render_component/2` per Phoenix version) to render `mini_map/1` against three handcrafted `MapView` structs: single-room, linear-three, off-map. Assert:
  - Single-room: exactly one `g.map-cell` element; one `title` inside it with the room's name; `map-cell--current` class present.
  - Linear-three: three `g.map-cell` elements; exactly two `line.map-line` elements (dedup verified); the middle room has `map-cell--current`.
  - Off-map: header is rendered but the SVG is absent OR the SVG canvas is `.map-canvas--off-map` empty; zero `g.map-cell` elements.
  - **Information-hiding**: no `data-room-id` (or any other `data-*`) attribute on `.map-line`. No `data-*` attribute on `.map-fog-cloud` or `.map-line--cross-region` (those don't exist yet but the assertion is forward-compat).
  - **No raw elevation integer**: regex-scan the rendered HTML for stray digits in unexpected places (specifically: no integer adjacent to "elevation" or alone in any header element).

**Checkpoint**: US1 fully functional. A freshly seeded player sees the Stone Atrium on the map with "Region · Blackmire" in the header. The mockup is replaced.

---

## Phase 4: User Story 2 — The map updates as the player moves (Priority: P1)

**Goal**: Movement triggers map re-render. Newly discovered rooms appear; current-room highlight follows the player; previously discovered rooms remain visible.

**Independent test**: Stand in the Atrium, open the map, type `north`. The Corridor appears as a new glyph and is highlighted; the Atrium retains its glyph without the current highlight; a line connects them.

- [X] T059 [US2] Extend `test/agenticrealms/world/map_view_test.exs` with US2 cases:
  - After a player moves between two rooms (simulated by directly updating `player_state.current_room_id` and inserting a `player_discovered_rooms` row), `MapView.for_player/1` returns the new room as `is_current?: true` and the old room as `is_current?: false`.
  - Two discovered, connected rooms render with a single `:normal` exit.
  - A fresh player who has discovered only the spawn room renders ONLY that room — no other Blackmire rooms appear even though they exist in the database.

  No new implementation tasks are needed for US2 — T055's `handle_info` clause for `%PlayerCurrentRoomChanged{}` and the discovery emission in T042 together make movement-driven map updates work. This phase is verification.

- [X] T060 [P] [US2] Extend `test/agenticrealms_web/components/game_components_mini_map_test.exs` (or add to the integration test in T080) with a sequence assertion: render the component with `single_room` fixture, then render again with `linear_three` fixture, assert the rendered HTML differs in the expected way (one → three glyphs; current highlight moves).

**Checkpoint**: US2 verified. Movement updates the map within the 1-second SC-002 latency budget.

---

## Phase 5: User Story 3 — One-way exits and fog-of-war info hiding (Priority: P1)

**Goal**: One-way exits look identical to two-way exits on the map (no arrowheads, no asymmetric styling). Exits toward map-visible but undiscovered rooms appear as fog-of-war stubs that do NOT reveal the destination room's identity.

**Independent test**: From the Library, a south exit leads to an undiscovered Cellar. The map shows a line extending south from the Library, ending in a fog-of-war marker. Hovering the marker reveals NO room name. The line for any one-way exit in the seed is visually indistinguishable from a two-way line.

### Fog stubs in MapView

- [X] T061 [US3] In `lib/agenticrealms/world/map_view.ex`, extend `build_normal_view/2` to emit `MapView.Exit{kind: :fog_stub, ...}` entries per `contracts/map-view.md`:
  - For each exit whose source room is in the rendered set AND whose target room is map_visible + has coordinates set BUT NOT in the player's discovered set, emit a `:fog_stub` entry.
  - `from_x`/`from_y` = source coords; `to_x`/`to_y` = source coords plus the direction's unit-vector step (one cell into the direction), computed via `Direction.Geometry.unit_vector/1` for planar exits. For vertical exits (Up/Down), a fog stub is NOT emitted — vertical exits to undiscovered rooms produce an Up/Down icon on the source room (see T067) but no fog line.
  - `direction` field is populated so the renderer can angle the stub correctly.
  - Verify: the `MapView.Exit` struct contains NO destination room id. Add an `assertion-by-contract` test below.

### Fog-stub renderer

- [X] T062 [US3] In `lib/agenticrealms_web/components/game_components.ex` `mini_map/1`, add an `:if/case` branch in the per-exit render path for `kind == :fog_stub`. Render:
  - A `<line class="map-fog-stub" stroke="url(#fog-fade)">` from `(from_x, from_y)` to `(to_x, to_y)` in screen coords.
  - A `<rect class="map-fog-cloud" fill="url(#fog-hatch)">` centered on `(to_x, to_y)`, 20×20 px.
  - NO `<title>` element. NO `data-room-name`. NO `data-room-id`.
- [X] T063 [US3] In `lib/agenticrealms_web/components/game_components.ex` `mini_map/1`, add an `<defs>` block at the top of the `<svg>` containing:
  - `<linearGradient id="fog-fade">` from full-opacity `var(--ink-dim)` at offset 0% to ~10% opacity at offset 100%.
  - `<pattern id="fog-hatch">` — a diagonal-hatch pattern using `var(--ink-faint)` strokes at 45°.
- [X] T064 [US3] In `assets/css/game.css`, add `.map-fog-stub` (stroke-width 2; `stroke-linecap: round`) and `.map-fog-cloud` rules. Style the fog cloud's hatch fill so it looks like a soft cloud at typical browser zoom levels.

### Information-hiding verification

- [X] T065 [P] [US3] Extend `test/agenticrealms/world/map_view_test.exs` with US3 cases using the `fog_stub` fixture from `research.md R10`:
  - A player who has discovered the source room but not the target produces one `MapView.Exit{kind: :fog_stub}` entry.
  - The `:fog_stub` entry's `to_x`/`to_y` differ from any rendered room's coords (it's a midway point, not a room).
  - The struct's fields do NOT include the target room's id (assert by checking the struct has no field named anything like `:target_id`, `:to_room_id`, etc. — the struct only has `kind`, `from_x`, `from_y`, `to_x`, `to_y`, `direction`).
  - One-way exit fixture: from A→B (one-way), with both rooms discovered, MapView emits ONE `:normal` exit (not two). Render dedup confirms.
- [X] T066 [P] [US3] Extend `test/agenticrealms_web/components/game_components_mini_map_test.exs` with US3 assertions:
  - The fog-stub fixture renders exactly one `line.map-fog-stub` and exactly one `rect.map-fog-cloud`.
  - The `.map-fog-stub` element has NO `title` child element.
  - The `.map-fog-cloud` element has NO `data-room-name`, `data-room-id`, or any other identifying attribute.
  - The one-way-exit fixture renders exactly one `line.map-line` (not two). Compare to a fixture with a reciprocal two-way pair — both render the same way visually.

**Checkpoint**: US3 fully functional. The map silently conceals one-way directions and undiscovered destinations.

---

## Phase 6: User Story 4 — Vertical exits + elevation filtering (Priority: P2)

**Goal**: Up/Down exits render as icons on the source room (top-right for Up, bottom-right for Down, both can appear simultaneously). The map filters to the player's current elevation; the previous floor's rooms disappear. The header shows above/below affordances when discovered rooms exist on other elevations.

**Independent test**: From the Atrium (elev=0, has Up icon), type `up`. The map filters to elev=1, the Atrium Loft is highlighted (with a Down icon), the below-rooms affordance pip appears. Type `down`. Back to elev=0; up affordance pip visible.

### Up/Down icon support in MapView

- [X] T067 [US4] In `lib/agenticrealms/world/map_view.ex`, extend the per-room build step to populate `has_up?` and `has_down?` on `MapView.Room`. For each rendered room, check its exits: if any `:up` exit exists whose target is `map_visible: true` and has coords set, `has_up?: true`. Same for `:down`. Hidden-target exits do NOT trigger the icon (FR-006). This requires preloading exits when fetching rooms; extend `Queries.rooms_in_region_at_elevation_within_viewport/4` to preload `:exits` (and the exit's target room enough to check `map_visible` and coord-set), or do a follow-up query.

### Elevation filtering + above/below affordances in MapView

- [X] T068 [US4] Add `has_discovered_rooms_at_elevations?/3` to `lib/agenticrealms/world/queries.ex` per `contracts/map-view.md`: given a region_id, a list of comparison-elevations (e.g., `[elev_above_1, elev_above_2, …]` if querying "above"; or simpler — accept a comparison operator and a reference elevation), and the player_id, returns a boolean. Implementation: a single `EXISTS` query joining `world_rooms` and `player_discovered_rooms`, filtered to the region and the elevation comparison.
  Simpler API: `has_discovered_rooms_above?(region_id, current_elevation, player_id)` and `has_discovered_rooms_below?(region_id, current_elevation, player_id)`. Two separate functions.
- [X] T069 [US4] In `lib/agenticrealms/world/map_view.ex` `build_normal_view/2`, populate `has_above_rooms?` and `has_below_rooms?` by calling the new Queries helpers. Confirm these are NOT populated in `build_off_map_view/1` (those return `false`).

### Renderer: Up/Down icons + above/below affordances

- [X] T070 [US4] In `lib/agenticrealms_web/components/game_components.ex` `mini_map/1`, inside each `g.map-cell`, render:
  - `<svg :if={r.has_up?} class="map-icon-up" ...>` with a chevron-up `<path d="M0 5 L4 1 L8 5" stroke="currentColor" stroke-width="1.5" fill="none" />` positioned at the top-right corner of the room rect (8 px wide; padded 3 px from the room's top and right).
  - `<svg :if={r.has_down?} class="map-icon-down" ...>` with a chevron-down `<path d="M0 1 L4 5 L8 1" .../>` at the bottom-right corner.
  Both can render simultaneously without overlap.
- [X] T071 [US4] In `lib/agenticrealms_web/components/game_components.ex` `mini_map/1`'s `.map-header`, add:
  - `<span :if={@map_view.has_above_rooms?} class="map-affordance-above" aria-label="Discovered rooms above"></span>` (a small chevron-up SVG inside).
  - `<span :if={@map_view.has_below_rooms?} class="map-affordance-below" aria-label="Discovered rooms below"></span>`.
  Both render side-by-side next to the region name. NO numeric content, NO integer.

### CSS for icons and affordances

- [X] T072 [US4] In `assets/css/game.css`, add:
  - `.map-icon-up`, `.map-icon-down` — color inherited from parent `.map-cell`; subtle stroke; `pointer-events: none` so they don't intercept hover.
  - `.map-affordance-above`, `.map-affordance-below` — small inline-flex items in the header; color `var(--ink-dim)` normally, `var(--player-dim)` when present.

### Tests for US4

- [X] T073 [P] [US4] Extend `test/agenticrealms/world/map_view_test.exs` with `multi_floor/0` fixture cases (per `research.md R10`):
  - From an elev-0 room with an Up exit, MapView returns the room with `has_up?: true`, `has_down?: false`; `has_above_rooms?: true`; `has_below_rooms?: false`.
  - From an elev-1 room with a Down exit, MapView returns `has_down?: true`, `has_up?: false`; `has_below_rooms?: true`; `has_above_rooms?: false`.
  - From a middle-landing room (elev=1) with both Up and Down exits, MapView returns `has_up?: true` AND `has_down?: true`.
  - From an elev-1 room, elev-0 rooms do NOT appear in `rooms` (elevation filter).
  - The `two_wing_house/0` fixture: at elev-1, both wings' discovered rooms appear, with NO line between them (disconnected components).
- [X] T074 [P] [US4] Extend `test/agenticrealms_web/components/game_components_mini_map_test.exs` with US4 assertions:
  - Multi-floor fixture renders the Up icon as `.map-icon-up` inside the correct room's group; ditto Down.
  - When both `has_up?` and `has_down?` are true on the same room, both icons render and don't visually overlap (assert by counting `.map-icon-up` and `.map-icon-down` elements).
  - The `.map-affordance-above` element appears in the header when `has_above_rooms?: true`, otherwise absent.
  - **No raw elevation integer**: scan the rendered HTML — the integer `1` or `0` for the current floor must NOT appear in any header text or attribute (regex `~r/\belevation\b/` returns no matches; header inner text is exactly the region name + possible whitespace).

**Checkpoint**: US4 fully functional. Multi-floor structures filter cleanly; up/down icons read correctly; no integer leak.

---

## Phase 7: User Story 5 — Hidden rooms and off-map render behavior (Priority: P2)

**Goal**: Rooms with `map_visible: false` never appear on the map, AND their connecting exits are suppressed (no line, no fog stub). When the player stands in a hidden or unmapped room, the map shows only the region name (FR-003a).

**Independent test**: From the Library, the west side shows no exit indication at all (the Hidden Vault to the west is `map_visible: false`). Walk west into the Vault. The map header still reads "Region · Blackmire" but the canvas is blank. Walk east back to the Library; the full map of discovered rooms reappears.

- [X] T075 [US5] Verify that `lib/agenticrealms/world/map_view.ex` (built in T051 and extended in T061) ALREADY suppresses:
  - Hidden rooms from `MapView.rooms` (covered by the `map_visible = true` filter in `Queries.rooms_in_region_at_elevation_within_viewport/4` from T049).
  - Exits to hidden rooms from `MapView.exits` (in `build_normal_view`, when classifying exits, target rooms with `map_visible: false` are SUPPRESSED ENTIRELY — no `:normal`, no `:fog_stub`, no `:cross_region` entry).
  - Exits FROM hidden rooms (the source room isn't in the rendered set, so no exits from it are considered).
  If any of these are not already in place from T051/T061, add the suppression now. Add an inline comment naming FR-006.
- [X] T076 [US5] Verify that `build_off_map_view/1` in `map_view.ex` is invoked when the player's current room has `map_visible: false` OR `map_x: nil` (the `off_map?/1` helper handles both). If the off-map branch was not implemented in T051, add it now.
- [X] T077 [P] [US5] Extend `test/agenticrealms/world/map_view_test.exs` with US5 cases:
  - `hidden_room/0` fixture: a room with `map_visible: false` does NOT appear in `MapView.rooms` even when discovered.
  - Exits TO the hidden room are suppressed entirely (zero entries of any kind in `MapView.exits` for that pair).
  - Exits FROM the hidden room are suppressed (the source isn't in the rendered set, so no entries appear).
  - `off_map/0` fixture (player standing in a hidden or unmapped room): `MapView.for_player/1` returns `off_map?: true`, `rooms: []`, `exits: []`, `has_above_rooms?: false`, `has_below_rooms?: false`. The `region_name` is still populated.
- [X] T078 [P] [US5] Extend `test/agenticrealms_web/components/game_components_mini_map_test.exs` with US5 assertions:
  - Hidden-room fixture: the rendered SVG contains zero glyphs for hidden rooms; no lines reach the hidden room's coords.
  - Off-map fixture: the SVG contains the region-name header but the `.map-canvas` is `.map-canvas--off-map` (or absent), with zero glyphs and zero lines.

**Checkpoint**: US5 fully functional. Hidden rooms are invisible to the map and their connecting exits leave no trace.

---

## Phase 8: User Story 6 — Cross-region transitions (Priority: P2)

**Goal**: Exits that cross from one region to another carry a distinct visual affordance (dashed line + portal glyph). When the player crosses regions, the map overlay swaps: the header shows the new region's name and only the new region's discovered rooms render.

**Independent test**: From the Border (in Blackmire), the east exit to Hollowvale Outskirts renders with a dashed line and a portal glyph; Outskirts is NOT drawn on the Blackmire map. Type `east`. The header swaps to "Region · Hollowvale"; only Hollowvale rooms appear; the cross-region affordance now points back to Blackmire from the Outskirts side.

### MapView: cross-region exits

- [ ] T079 [US6] In `lib/agenticrealms/world/map_view.ex` `build_normal_view/2`, extend the exit classification step to emit `MapView.Exit{kind: :cross_region, ...}` entries when the source room is in the rendered set AND the target room is map_visible + has coords + is in a DIFFERENT region. The terminator endpoint `(to_x, to_y)` is positioned one cell into the direction from the source (same convention as fog stubs — uses `Direction.Geometry.unit_vector/1`). The struct contains NO target room id, NO target region id, NO target region name (verified by tests).

### Renderer: dashed line + portal glyph

- [ ] T080 [US6] In `lib/agenticrealms_web/components/game_components.ex` `mini_map/1`, add a render branch for `kind == :cross_region`:
  - `<line class="map-line map-line--cross-region">` from source center to terminator endpoint.
  - `<circle class="map-portal" cx={to_x} cy={to_y} r="3">`.
  - NO `<title>` element. NO `data-*` attribute that names the destination.
- [ ] T081 [US6] In `assets/css/game.css`, add `.map-line--cross-region` (stroke `var(--player-dim)`, stroke-width 2, `stroke-dasharray: 4 3`) and `.map-portal` (fill `var(--player-dim)`).

### Region swap on movement

- [ ] T082 [US6] Verify the `handle_info/2` clause for `%PlayerCurrentRoomChanged{}` added in T055 correctly recomputes the `MapView` when the destination room is in a different region — the `MapView.for_player/1` query naturally picks up the new region via `current_room.region_id`. No new code is required; this task adds a comment to the handler explicitly naming FR-015 / SC-005 and confirming that region transitions flow through the same handler. Also confirm `GameLive` subscribes to the destination room's topic on region swap (existing pattern — already handled).

### Tests for US6

- [ ] T083 [P] [US6] Extend `test/agenticrealms/world/map_view_test.exs` with US6 cases using the `cross_region/0` fixture:
  - From a Blackmire room with an exit to a Hollowvale room, MapView emits one `MapView.Exit{kind: :cross_region}` entry; the Hollowvale room is NOT in `MapView.rooms`.
  - The `:cross_region` struct contains no field naming the target region.
  - When the player moves into Hollowvale, MapView returns `region_name: "Hollowvale"`, only Hollowvale rooms in `MapView.rooms`, and one `:cross_region` entry pointing back west to Blackmire.
- [ ] T084 [P] [US6] Extend `test/agenticrealms_web/components/game_components_mini_map_test.exs` with US6 assertions:
  - Cross-region fixture: exactly one `line.map-line--cross-region` element with `stroke-dasharray` set; exactly one `circle.map-portal` at its terminator end.
  - NO `title` child of the cross-region line or portal.
  - NO `data-region-name` or `data-room-name` attribute on the portal.

**Checkpoint**: US6 fully functional. Cross-region transitions swap the map within the SC-005 latency budget.

---

## Phase 9: User Story 7 — Hover tooltips (Priority: P3)

**Goal**: Hovering a rendered room glyph shows the room's friendly name in a styled tooltip. Fog-stub and cross-region portal hovers do NOT reveal any name.

**Independent test**: Hover the Atrium glyph → tooltip "Stone Atrium" appears. Hover a fog stub → no tooltip. Hover the cross-region portal glyph → no tooltip.

### Styled tooltip (server-rendered + minimal JS hook for positioning)

- [ ] T085 [US7] In `lib/agenticrealms_web/components/game_components.ex` `mini_map/1`, ensure each `.map-cell` group has its room name baked in via the existing `<title>` (already added in T054) AND a `data-room-name={r.name}` attribute on the `.map-cell` group itself. The data-attribute is for the JS hook (T086) to read on `mouseover`. Fog stubs and cross-region portals MUST NOT receive `data-room-name`.
- [ ] T086 [US7] In `lib/agenticrealms_web/live/game_live.html.heex`, add a ColocatedHook named `.MapTooltip` attached to the `<svg class="map-canvas">` element. The hook listens for `mouseover` and `mouseleave` on child elements with `data-room-name`. On `mouseover`, it pushes `tooltip:show` with `{name, x, y}` (computed from `event.clientX/Y`). On `mouseleave` it pushes `tooltip:hide`. The hook is ~15 lines of JS — modeled on the existing `.ScrollBottom` and `.StreamingText` colocated hooks.
- [ ] T087 [US7] In `lib/agenticrealms_web/live/game_live.ex`, handle the `tooltip:show` event by assigning `{room_name, x, y}` to the socket; `tooltip:hide` clears it. Render a `<div :if={@map_tooltip} class="map-tooltip" style={"left: #{@map_tooltip.x}px; top: #{@map_tooltip.y}px"}>{@map_tooltip.name}</div>` in `game_live.html.heex` (or in `player_view/1`).
- [ ] T088 [US7] In `assets/css/game.css`, add a `.map-tooltip` rule: absolutely positioned (overflows the SVG cleanly), small padding, `background: var(--bg-sunken)`, `border: 1px solid var(--line)`, `color: var(--ink)`, font from `var(--mono)`, `pointer-events: none`, fades in via a short CSS transition.

### Tests for US7

- [ ] T089 [P] [US7] Extend `test/agenticrealms_web/components/game_components_mini_map_test.exs` with US7 assertions:
  - Every `.map-cell` group has BOTH a `<title>` child (accessibility baseline) AND a `data-room-name` attribute.
  - The `data-room-name` attribute value matches the corresponding `MapView.Room.name`.
  - Fog stubs (`.map-fog-stub`, `.map-fog-cloud`) have NO `data-room-name`.
  - Cross-region elements (`.map-line--cross-region`, `.map-portal`) have NO `data-room-name`.

**Checkpoint**: US7 fully functional. Tooltips polish the map without compromising the FR-017 information-hiding rule.

---

## Phase 10: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup, dir-pad expansion, integration test, and final verification.

### Mockup cleanup

- [ ] T090 [P] In `lib/agenticrealms/game_data.ex`, DELETE `map_nodes/0` and `map_edges/0` (no longer used after T054/T055). Verify via `grep` that no caller remains.
- [ ] T091 [P] In `lib/agenticrealms/game_data.ex`, scan for any other map-mock references (commented or active) and remove them. The `GameData` module retains everything not related to the map mockup.

### Dir-pad expansion (R7 — 4 → 10 directions)

- [ ] T092 In `lib/agenticrealms_web/components/game_components.ex`, locate the existing `.dir-pad` markup (inline inside `mini_map/0` or `player_view/1`). EXTRACT it into a `dir_pad/1` function component (so it can be tested separately and so the panel layout is cleaner). EXPAND it per `research.md R7`:
  - 3×3 compass pad with all eight cardinal buttons (NW, N, NE in top row; W, look-center, E in middle; SW, S, SE in bottom). Each button is a `<button phx-click="submit_command" phx-value-command="<direction-name>" aria-label="<full direction>">` (or uses the existing direction-button event the project uses).
  - Separate Up/Down column to the right of the pad: stacked Up and Dn buttons.
  - The center "look" button issues the existing `look` command.
- [ ] T093 In `assets/css/game.css`, extend the `.dir-pad` rules to accommodate the new layout: keep the existing `grid-template-columns: repeat(3, 1fr)`, ensure the 9 buttons fit, and add a sibling `.dir-pad-vert` rule (or equivalent class) for the Up/Down column with `display: flex; flex-direction: column; gap: 4px`. Diagonal buttons share `.dir-pad button` styling; the look button gets a subtle visual distinction (e.g., dimmer border).
- [ ] T094 [P] Add a small render test for `dir_pad/1` in `test/agenticrealms_web/components/game_components_dir_pad_test.exs` (or extend the mini-map test file): assert all 8 compass buttons + Up + Dn + look render with their respective `aria-label`s.

### Integration test

- [ ] T095 Create `test/agenticrealms_web/live/game_live_maps_test.exs` with `@moduletag :integration`. Exercise US1–US7 in sequence against the seeded world:
  - US1: mount; assert map header reads "Region · Blackmire"; one room glyph; current-highlight on the Atrium.
  - US2: send a movement command (`north`); assert the Corridor appears, highlight moves.
  - US3: assert the map renders any one-way exit as a plain line (find one in the seed or fixture-set up via direct Repo inserts before the test runs); assert any undiscovered-visible exit renders as a fog stub with no name reveal.
  - US4: go up to the Loft; assert the header shows the below-rooms affordance; assert only Loft is in `rooms`; assert the Loft has a Down icon. Go down; assert the up affordance reappears.
  - US5: enter the Hidden Vault (via the cardinal command from the Library); assert the canvas is blank but the header still reads "Region · Blackmire".
  - US6: move to the Border; assert the cross-region affordance is visible; move east into Hollowvale; assert the header swaps to "Region · Hollowvale".
  - US7: assert that hovering (simulated via the `tooltip:show` event in LiveView's test framework) on a room produces the tooltip with the correct name; on a fog stub, no tooltip is shown.

### Final manual verification

- [ ] T096 Follow `quickstart.md` §1–§7 end-to-end on a developer machine. Confirm all acceptance behaviors visually. Capture any visual regressions and file follow-up tasks if needed.

### Success-criteria audit

- [ ] T097 [P] Open a fresh page, view source on the rendered map, and confirm: zero occurrences of the integer elevation in any HTML attribute or visible text (SC-008); zero `data-*` attributes that leak fog-stub destination names (FR-017); zero arrowhead markers on any `.map-line` element (SC-003).
- [ ] T098 [P] In `mix test` runs (full suite), assert no test references `GameData.map_nodes` or `GameData.map_edges` (the mockup symbols). `grep -r "map_nodes\|map_edges" test/` returns no hits.

---

## Dependencies

```text
Phase 1 (Setup)            → Phase 2 (Foundational)
Phase 2 (Foundational)     → Phases 3–9 (US1–US7) [hard prerequisite]

Within Phase 2:
  T007–T008  Direction module extension       (no deps inside phase 2; pure module)
  T009–T010  Direction.Geometry module        depends on T007 (canonical set); pure module
  T011–T012  Exits.Validator module           depends on T009; pure module
  T013–T021  Region aggregate (new)           (no deps on Direction modules)
  T022–T028  Room aggregate extension         depends on T013 (FK target); modifies existing aggregate
  T029       AddExit validator wire-up        depends on T011, T022; wires the Validator module into Commands.add_exit/3
  T030–T034  Migrations                       depends on T013, T022 (schemas exist in code first)
  T035–T044  Player aggregate extension       depends on T033 (table exists), T022 (room rows exist for FK); modifies existing World.Player aggregate to add discovered_room_ids + RecordRoomDiscovery + PlayerDiscoveredRoom
  T045–T047  Seed rewrite                     depends on EVERYTHING above in phase 2

Phases 3–9:
  US1 (P1, MVP)     → no dependencies on US2–US7
  US2 (P1)          → depends on US1 (renderer foundation)
  US3 (P1)          → depends on US1 (fog stubs extend the renderer)
  US4 (P2)          → depends on US1; otherwise independent
  US5 (P2)          → depends on US1; mostly verification
  US6 (P2)          → depends on US1, US3 (terminator math reuses unit_vector)
  US7 (P3)          → depends on US1 (data-room-name added to .map-cell)
```

## Parallel execution within phases

- **Phase 1**: T001–T006 are all `[P]` — six directory/config edits in different files.
- **Phase 2 — Direction / Geometry / Validator modules (pure modules, no aggregates)**: T008 [P] after T007. T010 [P] after T009. T012 [P] after T011.
- **Phase 2 — Region aggregate (new)**: T014, T015, T019, T020, T021 are `[P]` (different files, all gated on T013/T016/T017/T018 chain).
- **Phase 2 — Room aggregate extension (existing aggregate, modified)**: T023, T024 are `[P]` (different files), both after T022. T028 [P] after T027.
- **Phase 2 — Player aggregate extension — discovery (existing aggregate, modified)**: T035, T036, T037 are `[P]`. T043, T044 [P] after T042.
- **US1**: T048, T049, T050 are `[P]` (different functions in queries.ex but can be staged across separate commits). T053, T058 [P].
- **US3**: T065, T066 [P].
- **US4**: T073, T074 [P].
- **US5**: T077, T078 [P].
- **US6**: T083, T084 [P].
- **US7**: T089 [P].
- **Phase 10**: T090, T091 [P]. T097, T098 [P].

## Implementation Strategy

**MVP delivery target**: Phase 1 + Phase 2 + Phase 3 (US1) = a real map that replaces the mockup with a single discovered room glyph in the correct region. ~58 tasks.

**Incremental delivery beyond MVP**:
- +Phase 4 (US2): movement-driven updates (~2 tasks).
- +Phase 5 (US3): fog of war and info hiding (~6 tasks).
- +Phase 6 (US4): vertical exits and elevation (~8 tasks).
- +Phase 7 (US5): hidden rooms (~4 tasks).
- +Phase 8 (US6): cross-region (~6 tasks).
- +Phase 9 (US7): hover tooltip polish (~5 tasks).
- +Phase 10: cleanup, dir-pad, integration test, audit (~9 tasks).

**Total tasks**: 98.

**Suggested commit cadence**: one commit per phase (Phase 2 may split into Direction / Region / Room / Migration / Discovery / Seed sub-commits for review tractability). The destructive Phase-2 migration commit is paired with quickstart-documented event-store reset; never run T030–T034 against a non-fresh production environment.
