# Contract: mini_map/1 LiveView component

## Component signature

```elixir
attr :map_view, MapView, required: true
attr :cell_size_px, :integer, default: 56
attr :viewport_cells, :integer, default: 11
attr :node_padding_px, :integer, default: 4

def mini_map(assigns)
```

The component is a pure function of its inputs. No internal state, no LiveView events emitted (except the optional hover tooltip's `tooltip:show` / `tooltip:hide` via the small ColocatedHook described in research R6).

## Render output shape

```text
<div class="map-panel">
  <header class="map-header">
    <h4 class="map-region">{@map_view.region_name}</h4>
    <span :if={@map_view.has_above_rooms?} class="map-affordance-above" aria-label="Discovered rooms above" />
    <span :if={@map_view.has_below_rooms?} class="map-affordance-below" aria-label="Discovered rooms below" />
  </header>

  <svg
    :if={not @map_view.off_map?}
    class="map-canvas"
    width={@viewport_cells * @cell_size_px}
    height={@viewport_cells * @cell_size_px}
    viewBox={viewbox_for(@map_view, @viewport_cells, @cell_size_px)}
  >
    <defs>
      <linearGradient id="fog-fade" ...>
        <stop offset="0%" stop-color="var(--ink-dim)" stop-opacity="1" />
        <stop offset="100%" stop-color="var(--ink-dim)" stop-opacity="0.1" />
      </linearGradient>
      <pattern id="fog-hatch" ...> ... </pattern>
    </defs>

    <!-- Exits (drawn first so they sit under the room rects) -->
    <%= for e <- @map_view.exits do %>
      <.map_line exit={e} cell_size={@cell_size_px} />
    <% end %>

    <!-- Rooms -->
    <%= for r <- @map_view.rooms do %>
      <.map_room room={r} cell_size={@cell_size_px} padding={@node_padding_px} />
    <% end %>
  </svg>

  <div :if={@map_view.off_map?} class="map-canvas map-canvas--off-map" />
</div>
```

## Per-element rendering

### `<.map_room room={r} ...>`

```text
<g
  class={["map-cell", r.is_current? && "map-cell--current"]}
  transform={"translate(#{cell_x(r)}, #{cell_y(r)})"}
>
  <title>{r.name}</title>
  <rect class="map-rect" x={pad} y={pad} width={inner} height={inner} rx="4" />
  <svg :if={r.has_up?} class="map-icon-up" x={inner - icon_size - pad} y={pad} ...>
    <path d="M0 5 L4 1 L8 5" stroke="currentColor" stroke-width="1.5" fill="none" />
  </svg>
  <svg :if={r.has_down?} class="map-icon-down" x={inner - icon_size - pad} y={inner - icon_size - pad} ...>
    <path d="M0 1 L4 5 L8 1" stroke="currentColor" stroke-width="1.5" fill="none" />
  </svg>
</g>
```

**Notes**:
- `<title>` carries the room's display name → satisfies FR-016 accessibility baseline.
- The room id is NOT in any DOM attribute. (Internally a `phx-value-room-id` would be needed only for clickable rooms; click-to-move is out of scope, so no such attribute.)
- Up/Down icons are inline `<svg>` for tight scoping — they inherit `color` from the room's `.map-cell` class.

### `<.map_line exit={e} ...>`

```text
<%= case @exit.kind do %>
  <% :normal -> %>
    <line
      class="map-line"
      x1={center_x(@exit.from_x)} y1={center_y(@exit.from_y)}
      x2={center_x(@exit.to_x)} y2={center_y(@exit.to_y)}
    />

  <% :cross_region -> %>
    <line
      class="map-line map-line--cross-region"
      x1={center_x(@exit.from_x)} y1={center_y(@exit.from_y)}
      x2={center_x(@exit.to_x)} y2={center_y(@exit.to_y)}
    />
    <circle
      class="map-portal"
      cx={center_x(@exit.to_x)} cy={center_y(@exit.to_y)}
      r="3"
    />

  <% :fog_stub -> %>
    <line
      class="map-fog-stub"
      x1={center_x(@exit.from_x)} y1={center_y(@exit.from_y)}
      x2={center_x(@exit.to_x)} y2={center_y(@exit.to_y)}
      stroke="url(#fog-fade)"
    />
    <rect
      class="map-fog-cloud"
      x={fog_cloud_x(@exit)} y={fog_cloud_y(@exit)}
      width="20" height="20"
      fill="url(#fog-hatch)"
    />
<% end %>
```

**Notes**:
- Fog stubs and cross-region exits explicitly carry NO `<title>` element (FR-017).
- Fog stub stroke is a server-defined `<linearGradient>` from `var(--ink-dim)` full-opacity to ~10% opacity. The renderer DOES NOT include any data-* attribute identifying the destination room.
- Cross-region portal glyph is a small circle; could be swapped for a more thematic "doorway" icon in CSS without renderer changes.

## CSS targets

| Class                          | Styling                                                                                  |
|--------------------------------|------------------------------------------------------------------------------------------|
| `.map-panel`                   | The outer container; positions header above SVG.                                         |
| `.map-header`                  | Flex row with region name and above/below affordances.                                   |
| `.map-region`                  | Region name typography (matches the existing `<h4>` style in stat blocks).               |
| `.map-affordance-above`        | Small chevron-up pip; shown only when `has_above_rooms?` is true.                        |
| `.map-affordance-below`        | Small chevron-down pip.                                                                  |
| `.map-canvas`                  | The SVG. Fixed size = `viewport_cells × cell_size_px`. Centered in panel.                |
| `.map-canvas--off-map`         | When player is off-map: render only this blank canvas, no inner SVG content.             |
| `.map-cell`                    | Group wrapping a room. Sets `color` for icon inheritance.                                |
| `.map-cell--current`           | Bright fill on `.map-rect`, soft outer glow via `filter`.                                |
| `.map-cell:hover`              | Stroke brightens; cursor stays default (no click affordance).                            |
| `.map-rect`                    | The room glyph rectangle. Fill = `var(--bg-inset)`, stroke = `var(--ink-dim)`.           |
| `.map-icon-up`, `.map-icon-down` | Chevron icons. Color inherited from `.map-cell`.                                       |
| `.map-line`                    | Intra-region exit. Stroke = `var(--ink-dim)`, width 2.                                   |
| `.map-line--cross-region`      | Dashed (`stroke-dasharray: 4 3`). Stroke = `var(--player-dim)`.                          |
| `.map-portal`                  | Terminator glyph for cross-region. Fill = `var(--player-dim)`.                           |
| `.map-fog-stub`                | Line with the fog-fade gradient. No additional class needed.                             |
| `.map-fog-cloud`               | The hatched cloud at the fog-stub endpoint.                                              |

All colors reference existing CSS variables, so the phosphor/sepia/etc. themes apply without per-theme overrides.

## Hover tooltip (R6)

A `ColocatedHook` named `.MapTooltip` on the `<svg>` element listens for `mousemove`/`mouseleave` and emits `tooltip:show {room_name, x, y}` / `tooltip:hide` push-events to the LiveView. `GameLive` renders the tooltip in a separate absolutely-positioned `<div>` outside the SVG.

The hook never fires for fog stubs or cross-region portals — the renderer omits the `data-room-name` attribute on those elements (only `.map-cell` has it).

## Information-hiding checks (test surface)

The snapshot test (`game_components_mini_map_test.exs`) asserts:

- **No fog-stub `<title>` element**: `refute Floki.find(svg, ".map-fog-stub title")`.
- **No fog-cloud `data-*` attribute that names the destination**: `refute Floki.find(svg, ".map-fog-cloud[data-room-name]")`.
- **No raw elevation integer in any text node or attribute**: a recursive scan for digits matching `0..9` in unexpected positions (header, affordance labels, SVG content).
- **One line per unordered room pair**: assert that for the linear-three fixture, exactly two `.map-line` elements exist (A-B and B-C, not four for A→B, B→A, B→C, C→B).

## Accessibility

- Region name in `<h4>`.
- Above/Below affordances carry `aria-label`s ("Discovered rooms above" / "below").
- Each rendered room has an SVG `<title>` reading its display name.
- Fog stubs are silent on hover and to screen readers.
- The dir-pad buttons carry `aria-label`s for full direction names.

## Out of scope

- Click handlers on rooms (FR-018).
- Pan / zoom / scroll.
- Real-time animation on movement (acceptable to snap; no transition required).
