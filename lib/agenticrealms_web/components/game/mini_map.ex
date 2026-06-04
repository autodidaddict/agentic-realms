defmodule AgenticRealmsWeb.GameComponents.MiniMap do
  @moduledoc """
  Feature 012 — region mini-map rendering.

  The SVG viewBox lives in CELL UNITS. A "cell" is the 1x1 unit; room
  rects sit inside their cell with a small padding so connecting lines
  have visible run-up. The default zoom centers `default_zoom_cells`
  cells on the player's current room and the `.MapInteract` JS hook
  takes over mouse-wheel zoom and click-drag pan from there — local
  viewBox manipulation only, no server round-trip per mousemove.
  """

  use AgenticRealmsWeb, :html

  # Cell-unit constants (NOT module attributes accessed via @ in HEEx
  # — HEEx ~H treats @-prefixed names as assigns).
  @cell_inner_size 0.86
  @icon_size_cells 0.22
  # Distance from the room rect's edge to the nearest edge of the icon —
  # so the arrow never touches the rect border.
  @icon_inset_cells 0.06
  # The cross-region portal is a rotated diamond; its corner-to-corner
  # extent on the line of attack is `portal_size * √2 ≈ size * 1.414`,
  # so it visually "reads" larger than a same-size unrotated square.
  @portal_size_cells 0.06
  # Fog stubs retreat their visible endpoint inward from the cloud
  # center so the dashed stroke stops at the cloud's edge instead of
  # running into its middle.
  @fog_line_retreat 0.18

  attr :map_view, :map, required: true

  def mini_map(assigns) do
    {cx, cy} = assigns.map_view.viewport_center
    zoom = map_default_zoom_cells()
    half = zoom / 2.0

    # SVG viewBox lives in CELL UNITS. Default view is `zoom` cells
    # wide, centered on the player's current room. `.MapInteract`
    # owns mouse-wheel zoom and click-drag pan from there.
    initial_view_box = "#{cx - half} #{cy - half} #{zoom} #{zoom}"

    # Decoration dedupe: two fog stubs sharing a destination cell
    # composite to a darker spot; same for converging cross-region
    # portals. Render one decoration per (kind, to_x, to_y) — the
    # connector lines still all render in Pass 1 so each known source
    # visibly points at the cell.
    decorations =
      assigns.map_view.exits
      |> Enum.uniq_by(fn e -> {e.kind, e.to_x, e.to_y} end)

    assigns =
      assigns
      |> assign(:initial_view_box, initial_view_box)
      |> assign(:decorations, decorations)

    ~H"""
    <div class="map-panel">
      <h4 class="map-region">
        <span class="map-region-label">Region</span>
        <span class="map-region-sep">·</span>
        <span class="map-region-name">{@map_view.region_name || "—"}</span>

        <span
          :if={@map_view.has_above_rooms?}
          class="map-affordance map-affordance--above"
          aria-label="Discovered rooms above"
          title="Rooms above"
        >
          <svg width="10" height="10" viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg">
            <path d="M1 7 L5 2 L9 7" stroke="currentColor" stroke-width="1.5" fill="none" />
          </svg>
        </span>
        <span
          :if={@map_view.has_below_rooms?}
          class="map-affordance map-affordance--below"
          aria-label="Discovered rooms below"
          title="Rooms below"
        >
          <svg width="10" height="10" viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg">
            <path d="M1 3 L5 8 L9 3" stroke="currentColor" stroke-width="1.5" fill="none" />
          </svg>
        </span>
      </h4>

      <%= if @map_view.off_map? do %>
        <div class="map-canvas map-canvas--off-map"></div>
      <% else %>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".MapInteract">
          // Feature 012 — client-side map interaction. Combines:
          //   * styled hover tooltip (reads data-room-name from .map-cell)
          //   * mouse-wheel zoom around the cursor
          //   * click-drag pan
          //
          // All viewBox manipulation is local — no LiveView round-trip per
          // mousemove / wheel tick. The server re-emits a default viewBox
          // (3 cells centered on the player) on every movement; the user's
          // pan/zoom is reset on movement, which is the desired UX (we
          // always recenter on the player after they move).
          //
          // FR-017 information hiding: fog stubs and cross-region portals
          // do NOT carry data-room-name, so they silently no-op for the
          // tooltip path.
          export default {
            mounted() { this._wire(); this._installTooltip(); },
            updated() { this._wire(); },
            destroyed() {
              this.el.removeEventListener("mouseover", this._onOver);
              this.el.removeEventListener("mousemove", this._onMove);
              this.el.removeEventListener("mouseout", this._onOut);
              this.el.removeEventListener("wheel", this._onWheel);
              this.el.removeEventListener("mousedown", this._onDown);
              window.removeEventListener("mouseup", this._onUp);
              window.removeEventListener("mousemove", this._onPan);
              if (this._tip && this._tip.parentNode) {
                this._tip.parentNode.removeChild(this._tip);
              }
            },

            // ----- tooltip --------------------------------------------
            _installTooltip() {
              this._tip = document.createElement("div");
              this._tip.className = "map-tooltip";
              this._tip.style.display = "none";
              document.body.appendChild(this._tip);
            },
            _showTip(cell, x, y) {
              const name = cell.getAttribute("data-room-name");
              if (!name) return;
              this._tip.textContent = name;
              this._tip.style.left = (x + 12) + "px";
              this._tip.style.top = (y + 12) + "px";
              this._tip.style.display = "block";
            },
            _hideTip() { this._tip.style.display = "none"; },

            // ----- viewBox helpers ------------------------------------
            _getVB() {
              const v = this.el.getAttribute("viewBox").split(/\s+/).map(parseFloat);
              return { x: v[0], y: v[1], w: v[2], h: v[3] };
            },
            _setVB(vb) {
              this.el.setAttribute("viewBox", `${vb.x} ${vb.y} ${vb.w} ${vb.h}`);
            },
            // Convert screen-pixel (clientX, clientY) to viewBox coords.
            _screenToVB(clientX, clientY) {
              const rect = this.el.getBoundingClientRect();
              const vb = this._getVB();
              const sx = (clientX - rect.left) / rect.width;
              const sy = (clientY - rect.top) / rect.height;
              return { x: vb.x + sx * vb.w, y: vb.y + sy * vb.h };
            },

            // ----- wiring ---------------------------------------------
            _wire() {
              if (this._wired) return;
              this._wired = true;

              this._onOver = (ev) => {
                const cell = ev.target.closest("[data-room-name]");
                if (!cell) return;
                this._showTip(cell, ev.clientX, ev.clientY);
              };
              this._onMove = (ev) => {
                if (this._dragging) return; // suppress tooltip while panning
                const cell = ev.target.closest("[data-room-name]");
                if (!cell) { this._hideTip(); return; }
                this._showTip(cell, ev.clientX, ev.clientY);
              };
              this._onOut = (ev) => {
                if (this.el.contains(ev.relatedTarget)) return;
                this._hideTip();
              };
              this._onWheel = (ev) => {
                ev.preventDefault();
                const vb = this._getVB();
                const anchor = this._screenToVB(ev.clientX, ev.clientY);
                // Positive deltaY = wheel down = zoom out; multiplier > 1
                const factor = Math.exp(ev.deltaY * 0.0015);
                let nw = vb.w * factor;
                let nh = vb.h * factor;
                // Clamp: never below 1 cell or above 200 cells (regions
                // are capped around that size in the spec).
                nw = Math.max(1, Math.min(200, nw));
                nh = Math.max(1, Math.min(200, nh));
                // Keep the cursor anchor stable.
                const nx = anchor.x - (anchor.x - vb.x) * (nw / vb.w);
                const ny = anchor.y - (anchor.y - vb.y) * (nh / vb.h);
                this._setVB({ x: nx, y: ny, w: nw, h: nh });
              };
              this._onDown = (ev) => {
                if (ev.button !== 0) return; // left button only
                ev.preventDefault();
                this._dragging = true;
                this._dragOriginX = ev.clientX;
                this._dragOriginY = ev.clientY;
                this._dragVB = this._getVB();
                this._hideTip();
                this.el.style.cursor = "grabbing";
              };
              this._onPan = (ev) => {
                if (!this._dragging) return;
                // Pan = subtract the cursor delta (in viewBox coords)
                // from the viewBox at drag-start so the cursor stays
                // anchored to the same world point.
                const rect = this.el.getBoundingClientRect();
                const dx = ((ev.clientX - this._dragOriginX) / rect.width) * this._dragVB.w;
                const dy = ((ev.clientY - this._dragOriginY) / rect.height) * this._dragVB.h;
                this._setVB({
                  x: this._dragVB.x - dx,
                  y: this._dragVB.y - dy,
                  w: this._dragVB.w,
                  h: this._dragVB.h,
                });
              };
              this._onUp = () => {
                if (!this._dragging) return;
                this._dragging = false;
                this.el.style.cursor = "";
              };

              this.el.addEventListener("mouseover", this._onOver);
              this.el.addEventListener("mousemove", this._onMove);
              this.el.addEventListener("mouseout", this._onOut);
              this.el.addEventListener("wheel", this._onWheel, { passive: false });
              this.el.addEventListener("mousedown", this._onDown);
              window.addEventListener("mouseup", this._onUp);
              window.addEventListener("mousemove", this._onPan);
            }
          }
        </script>

        <svg
          id="map-canvas-svg"
          phx-hook=".MapInteract"
          class="map-canvas"
          viewBox={@initial_view_box}
          preserveAspectRatio="xMidYMid meet"
          xmlns="http://www.w3.org/2000/svg"
        >
          <defs></defs>

          <%!-- Pass 1: connector lines — drawn under everything. --%>
          <.map_exit_line :for={e <- @map_view.exits} exit={e} />

          <%!-- Pass 2: room glyphs — sit on top of the lines. --%>
          <.map_cell :for={r <- @map_view.rooms} room={r} />

          <%!-- Pass 3: endpoint decorations (fog clouds, cross-region
                portal glyphs) — drawn LAST so they sit above the player's
                current-room glyph and its glow, otherwise they get buried
                when the portal coincides with the player's room. Deduped
                upstream so two fog stubs sharing a destination cell
                produce a single cloud. --%>
          <.map_exit_decoration :for={e <- @decorations} exit={e} />
        </svg>
      <% end %>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Pass 1: connector lines under everything.
  # ────────────────────────────────────────────────────────────

  attr :exit, :map, required: true

  defp map_exit_line(assigns) do
    {fog_to_x, fog_to_y} = fog_line_endpoint(assigns.exit)

    assigns =
      assigns
      |> assign(:fog_to_x, fog_to_x)
      |> assign(:fog_to_y, fog_to_y)

    ~H"""
    <%= case @exit.kind do %>
      <% :normal -> %>
        <line
          class="map-line map-line--normal"
          x1={@exit.from_x}
          y1={@exit.from_y}
          x2={@exit.to_x}
          y2={@exit.to_y}
          vector-effect="non-scaling-stroke"
        />
      <% :fog_stub -> %>
        <line
          class="map-line map-fog-stub"
          x1={@exit.from_x}
          y1={@exit.from_y}
          x2={@fog_to_x}
          y2={@fog_to_y}
          vector-effect="non-scaling-stroke"
        />
      <% :cross_region -> %>
        <line
          class="map-line map-line--cross-region"
          x1={@exit.from_x}
          y1={@exit.from_y}
          x2={@exit.to_x}
          y2={@exit.to_y}
          vector-effect="non-scaling-stroke"
        />
    <% end %>
    """
  end

  defp fog_line_endpoint(%{kind: :fog_stub, from_x: fx, from_y: fy, to_x: tx, to_y: ty}) do
    dx = tx - fx
    dy = ty - fy
    mag = :math.sqrt(dx * dx + dy * dy)

    if mag > 0 do
      ux = dx / mag
      uy = dy / mag
      {tx - ux * @fog_line_retreat, ty - uy * @fog_line_retreat}
    else
      {tx, ty}
    end
  end

  defp fog_line_endpoint(%{to_x: tx, to_y: ty}), do: {tx, ty}

  # ────────────────────────────────────────────────────────────
  # Pass 2: room glyphs (rect + up/down icons inside).
  # ────────────────────────────────────────────────────────────

  attr :room, :map, required: true

  defp map_cell(assigns) do
    # Cell centered at (room.x, room.y). Rect occupies a square inside
    # the cell. Up/Down icons sit inside the room rect with clear
    # padding (@icon_inset_cells) on every side so they never touch
    # the border.
    inner = @cell_inner_size
    icon = @icon_size_cells
    inset = @icon_inset_cells

    rect_x = assigns.room.x - inner / 2
    rect_y = assigns.room.y - inner / 2
    # Right edge of icon sits @inset cells inside the rect's right edge.
    icon_x = assigns.room.x + inner / 2 - inset - icon
    # Top edge of UP icon: @inset below the rect's top edge.
    icon_up_y = assigns.room.y - inner / 2 + inset
    # Bottom edge of DOWN icon: @inset above the rect's bottom edge.
    icon_down_y = assigns.room.y + inner / 2 - inset - icon

    assigns =
      assigns
      |> assign(:rect_x, rect_x)
      |> assign(:rect_y, rect_y)
      |> assign(:icon_x, icon_x)
      |> assign(:icon_up_y, icon_up_y)
      |> assign(:icon_down_y, icon_down_y)
      |> assign(:cell_inner, inner)
      |> assign(:icon_size, icon)

    ~H"""
    <g
      class={["map-cell", @room.is_current? && "map-cell--current"]}
      data-room-name={@room.name}
      aria-label={@room.name}
    >
      <rect
        class="map-rect"
        x={@rect_x}
        y={@rect_y}
        width={@cell_inner}
        height={@cell_inner}
        rx="0.08"
        vector-effect="non-scaling-stroke"
      />

      <%!-- Simple up/down arrows (shaft + chevron head). --%>
      <svg
        :if={@room.has_up?}
        class="map-icon-up"
        x={@icon_x}
        y={@icon_up_y}
        width={@icon_size}
        height={@icon_size}
        viewBox="0 0 8 8"
        overflow="visible"
      >
        <path
          d="M4 7 L4 1 M1.5 3.5 L4 1 L6.5 3.5"
          stroke="currentColor"
          stroke-width="1.5"
          fill="none"
          stroke-linecap="round"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
        />
      </svg>

      <svg
        :if={@room.has_down?}
        class="map-icon-down"
        x={@icon_x}
        y={@icon_down_y}
        width={@icon_size}
        height={@icon_size}
        viewBox="0 0 8 8"
        overflow="visible"
      >
        <path
          d="M4 1 L4 7 M1.5 4.5 L4 7 L6.5 4.5"
          stroke="currentColor"
          stroke-width="1.5"
          fill="none"
          stroke-linecap="round"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
        />
      </svg>
    </g>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Pass 3: endpoint decorations (fog clouds, cross-region portals).
  # Drawn LAST so they sit above the player's current-room glow when
  # endpoints coincide. No data-room-name / aria-label per FR-007 /
  # FR-008 / FR-017 information hiding.
  # ────────────────────────────────────────────────────────────

  attr :exit, :map, required: true

  defp map_exit_decoration(assigns) do
    portal = @portal_size_cells

    assigns =
      assigns
      |> assign(:portal_x, assigns.exit.to_x - portal / 2)
      |> assign(:portal_y, assigns.exit.to_y - portal / 2)
      |> assign(:portal_size, portal)

    ~H"""
    <%= case @exit.kind do %>
      <% :normal -> %>
      <% :fog_stub -> %>
        <%!-- Soft cloud built from overlapping circles. Reads as a
              fluffy puff at the line endpoint instead of a hatched
              tile. No title/aria — FR-007 / FR-017 information hiding. --%>
        <g class="map-fog-cloud" transform={"translate(#{@exit.to_x} #{@exit.to_y})"}>
          <circle cx="-0.13" cy="0.02" r="0.08" />
          <circle cx="-0.05" cy="-0.07" r="0.10" />
          <circle cx="0.05" cy="-0.09" r="0.11" />
          <circle cx="0.13" cy="-0.02" r="0.09" />
          <circle cx="0.06" cy="0.06" r="0.08" />
          <circle cx="-0.05" cy="0.07" r="0.075" />
        </g>
      <% :cross_region -> %>
        <rect
          class="map-portal"
          x={@portal_x}
          y={@portal_y}
          width={@portal_size}
          height={@portal_size}
          transform={"rotate(45 #{@exit.to_x} #{@exit.to_y})"}
        />
    <% end %>
    """
  end

  defp map_default_zoom_cells do
    Application.get_env(:agenticrealms, AgenticRealms.MapRenderer, [])
    |> Keyword.get(:default_zoom_cells, 3)
  end
end
