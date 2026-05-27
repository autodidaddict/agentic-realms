defmodule AgenticRealmsWeb.GameComponents do
  @moduledoc """
  Game-specific UI function components for Agentic Realms.
  Provides all components for the player and wizard views.
  """
  use AgenticRealmsWeb, :html

  alias AgenticRealms.GameData

  # ────────────────────────────────────────────────────────────
  # HP Bar
  # ────────────────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :cur, :integer, required: true
  attr :max, :integer, required: true
  attr :kind, :string, required: true

  def hp_bar(assigns) do
    pct = max(0, min(1, assigns.cur / assigns.max))
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div>
      <div class="stat-label">
        <span>{@label}</span>
        <span class="val">{@cur} / {@max}</span>
      </div>
      <div class={"bar #{@kind}"}>
        <i style={"transform: scaleX(#{@pct})"}></i>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # HUD Card
  # ────────────────────────────────────────────────────────────

  attr :title, :string, required: true
  attr :count, :string, default: nil
  attr :modal_type, :string, required: true
  slot :inner_block, required: true

  def hud_card(assigns) do
    ~H"""
    <div class="hud-card">
      <button class="hud-card-head" phx-click="open_modal" phx-value-modal={@modal_type}>
        <span class="title">{@title}</span>
        <span style="display: flex; align-items: center; gap: 8px;">
          <span :if={@count} class="count">{@count}</span>
          <svg
            class="expand-icon"
            viewBox="0 0 10 10"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
          >
            <path d="M1 4h3V1 M9 4V1H6 M1 6v3h3 M9 6v3H6" />
          </svg>
        </span>
      </button>
      <div class="hud-card-body">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Log Entry
  # ────────────────────────────────────────────────────────────

  attr :entry, :map, required: true

  def log_entry(%{entry: %{kind: :room, room: %AgenticRealms.World.RoomView{}}} = assigns) do
    ~H"""
    <div class="log-entry room">
      <div class="room-head">
        <span class="room-name">{@entry.room.name}</span>
      </div>
      <div class="room-body">{@entry.room.description}</div>
      <div :if={@entry.room.exits != []} class="exits">
        <button
          :for={exit <- @entry.room.exits}
          class="exit-chip"
          phx-click="submit_command"
          phx-value-text={exit.direction}
        >
          <span class="arrow">→</span>
          <span>{exit.direction} · {exit.target_name}</span>
        </button>
      </div>
      <div :if={@entry.room.objects != [] or @entry.room.other_players != []} class="entities">
        <span :for={{obj, idx} <- Enum.with_index(@entry.room.objects)}>
          <span class="entity item">{obj.name}</span>
          <span :if={idx < length(@entry.room.objects) - 1 or @entry.room.other_players != []}>
            ·
          </span>
        </span>
        <span :for={{p, idx} <- Enum.with_index(@entry.room.other_players)}>
          <span class="entity player-other">{p.username}</span>
          <span :if={idx < length(@entry.room.other_players) - 1}> · </span>
        </span>
      </div>
      <div :if={@entry.room.npcs != []} class="room-section also-here">
        <span class="room-section-label">Also here:</span>
        <span :for={{npc, idx} <- Enum.with_index(@entry.room.npcs)} class="also-here-entry">
          <span class="entity npc">{npc.name}</span><span
            :if={npc.short_description not in [nil, ""]}
            class="also-here-short"
          > — {npc.short_description}</span><span :if={idx < length(@entry.room.npcs) - 1}> · </span>
        </span>
      </div>
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :room}} = assigns) do
    ~H"""
    <div class="log-entry room">
      <div class="room-head">
        <span class="room-name">{@entry.room.name}</span>
        <span>· {String.slice(@entry.room.desc, 0..30)}...</span>
        <span class="room-coord">{@entry.room.coord}</span>
      </div>
      <div class="room-body">{@entry.room.desc}</div>
      <div class="exits">
        <button :for={exit <- @entry.room.exits} class="exit-chip">
          <span class="arrow">→</span>
          <span>{exit.dir} · {exit.to}</span>
        </button>
      </div>
      <div class="entities">
        <span :for={{entity, idx} <- Enum.with_index(@entry.room.entities)}>
          <span class={"entity #{entity.type}"}>{entity.name}</span>
          <span :if={idx < length(@entry.room.entities) - 1}> · </span>
        </span>
      </div>
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :detail, target_kind: :object}} = assigns) do
    ~H"""
    <div class="log-entry detail detail-object">
      <div class="detail-head">
        <span class="detail-name">{@entry.name}</span>
      </div>
      <div class="detail-body">{@entry.long_description}</div>
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :detail, target_kind: :player}} = assigns) do
    ~H"""
    <div class="log-entry detail detail-player">
      <span class="detail-name">{@entry.name}</span> is a player.
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :detail, target_kind: :npc}} = assigns) do
    ~H"""
    <div class="log-entry detail detail-npc">
      <div class="detail-head">
        <span class="detail-name">{@entry.name}</span>
      </div>
      <div class="detail-body">{@entry.long_description}</div>
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :narrate}} = assigns) do
    ~H"""
    <div class="log-entry narrate">{@entry.text}</div>
    """
  end

  # Feature 009 — behavior-sourced NPC speech. Attributed: <name> says, "text".
  def log_entry(%{entry: %{kind: :npc_speech}} = assigns) do
    ~H"""
    <div class="log-entry speech speech-npc">
      <span class="who">{@entry.actor_name}</span> says, &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  # Feature 009 — behavior-sourced room narration. NO attribution — just the
  # line, rendered as ambient narration. No "X says" framing, no quotes.
  def log_entry(%{entry: %{kind: :room_speech}} = assigns) do
    ~H"""
    <div class="log-entry narrate narrate-room">{@entry.text}</div>
    """
  end

  # Feature 011 — emote actions (third-person narration). Three flavors:
  # room (ambient, no attribution), NPC (name prepended), object (name
  # prepended). No "says" wrapper, no quotes — just narrative text. Uses
  # the `ambient` base class (NOT `narrate`) so ticking emotes don't
  # carry feature 009's drop-cap styling — that styling was designed
  # for one-shot arrival narration and is too heavy for repeating ticks.

  def log_entry(%{entry: %{kind: :room_emote}} = assigns) do
    ~H"""
    <div class="log-entry ambient ambient-room">{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :npc_emote}} = assigns) do
    ~H"""
    <div class="log-entry ambient ambient-npc">
      <span class="who">{@entry.actor_name}</span> {@entry.text}
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :object_emote}} = assigns) do
    ~H"""
    <div class="log-entry ambient ambient-object">
      <span class="who">{@entry.actor_name}</span> {@entry.text}
    </div>
    """
  end

  # Feature 010 — private chat reply (speech mode). Visually mirrors :npc_speech
  # but on the private surface. The `speech-chat` class lets CSS distinguish
  # public NPC speech from a chat-private utterance if desired.
  def log_entry(%{entry: %{kind: :chat_speech}} = assigns) do
    ~H"""
    <div class="log-entry speech speech-npc speech-chat">
      <span class="who">{@entry.actor_name}</span> says, &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  # Feature 010 — private chat reply (emote mode). Third-person narration
  # attributed to the NPC by name. Mirrors the existing :emote_action shape.
  def log_entry(%{entry: %{kind: :chat_emote}} = assigns) do
    ~H"""
    <div class="log-entry emote emote-chat">
      <span class="who">{@entry.actor_name}</span> {@entry.text}
    </div>
    """
  end

  # Feature 010 — chat-frame system message. `kind_variant` discriminates
  # CSS class for styling (`chat-new`, `chat-continuing`, `chat-fallback`,
  # `chat-in-flight`).
  def log_entry(%{entry: %{kind: :chat_system}} = assigns) do
    variant_class =
      case assigns.entry[:kind_variant] do
        :chat_new -> "chat-new"
        :chat_continuing -> "chat-continuing"
        :chat_fallback -> "chat-fallback"
        :chat_in_flight_rejection -> "chat-in-flight"
        _ -> "chat-other"
      end

    assigns = Phoenix.Component.assign(assigns, :variant_class, variant_class)

    ~H"""
    <div class={"log-entry chat-system " <> @variant_class}>{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :cmd}} = assigns) do
    ~H"""
    <div class="log-entry cmd">{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :said}} = assigns) do
    ~H"""
    <div class="log-entry said">
      <span class="who">{@entry.who}</span> says, &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :whisper}} = assigns) do
    ~H"""
    <div class="log-entry whisper">{@entry.text}</div>
    """
  end

  def log_entry(%{entry: %{kind: :system}} = assigns) do
    ~H"""
    <div class="log-entry system">{@entry.text}</div>
    """
  end

  # Feature 004 — Player Communication
  # All `text` and `actor` values come from player input and MUST be rendered
  # via HEEx auto-escaping (default `{ @entry.text }` interpolation). FR-024.

  def log_entry(%{entry: %{kind: :speech}} = assigns) do
    ~H"""
    <div class="log-entry speech">
      <span class="who">{@entry.actor}</span> says, &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :speech_self}} = assigns) do
    ~H"""
    <div class="log-entry speech speech-self">
      <span class="who">You</span> say, &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :emote_action}} = assigns) do
    ~H"""
    <div class="log-entry emote">
      <span class="who">{@entry.actor}</span> {@entry.text}
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :private_tell_in}} = assigns) do
    ~H"""
    <div class="log-entry private private-tell">
      <em><span class="who">{@entry.actor}</span> tells you,</em> &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :private_tell_out}} = assigns) do
    ~H"""
    <div class="log-entry private private-tell private-self">
      <em>You tell <span class="who">{@entry.recipient}</span>,</em> &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :private_whisper_in}} = assigns) do
    ~H"""
    <div class="log-entry private private-whisper">
      <em><span class="who">{@entry.actor}</span> whispers to you,</em> &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :private_whisper_out}} = assigns) do
    ~H"""
    <div class="log-entry private private-whisper private-self">
      <em>You whisper to <span class="who">{@entry.recipient}</span>,</em> &ldquo;{@entry.text}&rdquo;
    </div>
    """
  end

  def log_entry(%{entry: %{kind: :combat}} = assigns) do
    ~H"""
    <div class="log-entry combat">
      <span class="combat-swing">HIT</span>
      <span>{@entry.text}</span>
      <span class="combat-num">−{@entry.dmg}</span>
      <div class="combat-bar">
        <i style={"transform: scaleX(#{@entry.pct})"}></i>
      </div>
    </div>
    """
  end

  def log_entry(assigns) do
    ~H"""
    """
  end

  # ────────────────────────────────────────────────────────────
  # Stats Panel
  # ────────────────────────────────────────────────────────────

  attr :stats, :map, required: true
  attr :inventory, :list, required: true
  attr :quests, :list, required: true
  attr :presence, :list, required: true
  attr :layout, :string, required: true

  def stats_panel(assigns) do
    ~H"""
    <aside class="p-stats">
      <div class="hud-card">
        <button class="hud-card-head" phx-click="open_modal" phx-value-modal="stats">
          <span class="title">Character</span>
          <span style="display: flex; align-items: center; gap: 8px;">
            <span class="count">{@stats.class}</span>
            <svg
              class="expand-icon"
              viewBox="0 0 10 10"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
            >
              <path d="M1 4h3V1 M9 4V1H6 M1 6v3h3 M9 6v3H6" />
            </svg>
          </span>
        </button>
        <div class="hud-card-body">
          <div style="display: grid; grid-template-columns: auto 1fr; gap: 10px; align-items: center; margin-bottom: 12px;">
            <div class="sigil">V</div>
            <div>
              <div class="who-name">{@stats.name}</div>
              <div class="who-class">{@stats.class}</div>
            </div>
          </div>
          <.hp_bar label="Health" cur={@stats.hp.cur} max={@stats.hp.max} kind="hp" />
          <div style="height: 8px" />
          <.hp_bar label="Mana" cur={@stats.mp.cur} max={@stats.mp.max} kind="mp" />
          <div style="height: 8px" />
          <.hp_bar label="Experience" cur={@stats.xp.cur} max={@stats.xp.max} kind="xp" />
        </div>
      </div>

      <%= if @layout != "minimal" do %>
        <.hud_card title="Inventory" count={Integer.to_string(length(@inventory))} modal_type="inv">
          <div class="inv-list">
            <div :if={@inventory == []} style="font-size: 11px; color: var(--ink-faint);">
              (empty)
            </div>
            <div :for={item <- Enum.take(@inventory, 5)} class="row">
              <span>{item.name}</span>
            </div>
            <div
              :if={length(@inventory) > 5}
              style="font-size: 10px; color: var(--ink-faint); margin-top: 4px; letter-spacing: 0.08em;"
            >
              + {length(@inventory) - 5} more...
            </div>
          </div>
        </.hud_card>

        <.hud_card title="Quest Log" count={"#{length(@quests)} active"} modal_type="quests">
          <div
            :for={{quest, idx} <- Enum.with_index(@quests)}
            class="quest-item"
            style={if idx == length(@quests) - 1, do: "margin-bottom: 0;", else: ""}
          >
            <div class="qt">{quest.title}</div>
            <div class="qp">{quest.progress}</div>
          </div>
        </.hud_card>

        <.hud_card title="Present" count={"#{length(@presence)} here"} modal_type="presence">
          <div
            :if={@presence == []}
            style="font-size: 11px; color: var(--ink-faint);"
          >
            (no one else)
          </div>
          <div :for={p <- @presence} class="presence-row">
            <span class="presence-dot" />
            <span>{p.username}</span>
          </div>
        </.hud_card>
      <% end %>
    </aside>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Mini Map
  # ────────────────────────────────────────────────────────────

  attr :map_view, :map, required: true

  def mini_map(assigns) do
    {cx, cy} = assigns.map_view.viewport_center
    zoom = map_default_zoom_cells()
    half = zoom / 2.0

    # SVG viewBox lives in CELL UNITS. Default view is `zoom` cells wide,
    # centered on the player's current room. The .MapInteract JS hook
    # owns mouse-wheel zoom and click-drag pan from there — it rewrites
    # the viewBox attribute locally without server round-trips.
    initial_view_box = "#{cx - half} #{cy - half} #{zoom} #{zoom}"

    assigns = assign(assigns, :initial_view_box, initial_view_box)

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
          <defs>
            <linearGradient
              id="fog-fade"
              x1="0%"
              y1="0%"
              x2="100%"
              y2="0%"
              gradientUnits="objectBoundingBox"
            >
              <stop offset="0%" stop-color="var(--ink-dim)" stop-opacity="1" />
              <stop offset="100%" stop-color="var(--ink-dim)" stop-opacity="0.1" />
            </linearGradient>
            <pattern
              id="fog-hatch"
              patternUnits="userSpaceOnUse"
              width="6"
              height="6"
              patternTransform="rotate(45)"
            >
              <line x1="0" y1="0" x2="0" y2="6" stroke="var(--ink-faint)" stroke-width="1" />
            </pattern>
          </defs>

          <%!-- Pass 1: connector lines — drawn under everything. --%>
          <.map_exit_line :for={e <- @map_view.exits} exit={e} />

          <%!-- Pass 2: room glyphs — sit on top of the lines. --%>
          <.map_cell :for={r <- @map_view.rooms} room={r} />

          <%!-- Pass 3: endpoint decorations (fog clouds, cross-region
                portal glyphs) — drawn LAST so they sit above the player's
                current-room glyph and its glow, otherwise they get buried
                when the portal coincides with the player's room. --%>
          <.map_exit_decoration :for={e <- @map_view.exits} exit={e} />
        </svg>
      <% end %>

    </div>
    """
  end

  # Coordinates are CELL UNITS throughout. The SVG viewBox sets the scale.
  # A "cell" is the 1x1 unit; room rects sit inside their cell with a
  # small padding so connecting lines have visible run-up. These are
  # plain compile-time constants — NOT module attributes (HEEx ~H blocks
  # treat @-prefixed names as assigns).
  @cell_inner_size 0.86
  @icon_size_cells 0.24
  @cloud_size_cells 0.32
  # The cross-region portal is a rotated diamond; its corner-to-corner
  # extent on the line of attack is `portal_size * √2 ≈ size * 1.414`,
  # so it visually "reads" larger than a same-size unrotated square. Keep
  # it deliberately small — the dashed line carries most of the meaning.
  @portal_size_cells 0.06

  attr :exit, :map, required: true

  # Pass 1: just the line. Sits under room glyphs.
  defp map_exit_line(assigns) do
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
          x2={@exit.to_x}
          y2={@exit.to_y}
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

  attr :exit, :map, required: true

  # Pass 3: fog clouds + cross-region portal glyphs. Drawn on top of room
  # glyphs so they're not buried by the player's current-room rect or its
  # glow when the portal endpoint coincides with the player's room. No
  # data-room-name / aria-label (FR-007 / FR-008 / FR-017).
  defp map_exit_decoration(assigns) do
    cloud = @cloud_size_cells
    portal = @portal_size_cells

    assigns =
      assigns
      |> assign(:cloud_x, assigns.exit.to_x - cloud / 2)
      |> assign(:cloud_y, assigns.exit.to_y - cloud / 2)
      |> assign(:cloud_size, cloud)
      |> assign(:portal_x, assigns.exit.to_x - portal / 2)
      |> assign(:portal_y, assigns.exit.to_y - portal / 2)
      |> assign(:portal_size, portal)

    ~H"""
    <%= case @exit.kind do %>
      <% :normal -> %>
      <% :fog_stub -> %>
        <rect
          class="map-fog-cloud"
          x={@cloud_x}
          y={@cloud_y}
          width={@cloud_size}
          height={@cloud_size}
          fill="url(#fog-hatch)"
        />
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

  attr :room, :map, required: true

  defp map_cell(assigns) do
    # Cell centered at (room.x, room.y). Rect occupies a square inside the
    # cell with `@cell_inner_size` slack on every side. Up/Down icons sit
    # at the room's top-right / bottom-right corners in cell units.
    inner = @cell_inner_size
    icon = @icon_size_cells

    rect_x = assigns.room.x - inner / 2
    rect_y = assigns.room.y - inner / 2
    icon_x = assigns.room.x + inner / 2 - icon

    assigns =
      assigns
      |> assign(:rect_x, rect_x)
      |> assign(:rect_y, rect_y)
      |> assign(:icon_x, icon_x)
      |> assign(:icon_up_y, assigns.room.y - inner / 2)
      |> assign(:icon_down_y, assigns.room.y + inner / 2 - icon)
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

      <%!-- Staircase silhouettes (3 steps each). Conveys "this room has
            stairs" — semantically richer than a directional chevron and
            visually consistent with the detailed line-icon style of the
            folded-map toggle. --%>
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
          d="M1 7 L1 5 L3 5 L3 3 L5 3 L5 1 L7 1"
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
          d="M1 1 L3 1 L3 3 L5 3 L5 5 L7 5 L7 7"
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

  defp map_default_zoom_cells do
    Application.get_env(:agenticrealms, AgenticRealms.MapRenderer, [])
    |> Keyword.get(:default_zoom_cells, 3)
  end

  # ────────────────────────────────────────────────────────────
  # Modal Shell
  # ────────────────────────────────────────────────────────────

  attr :title, :string, required: true
  attr :glyph, :string, default: nil
  attr :foot_hint, :string, default: nil
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div class="gm-backdrop" phx-window-keydown="close_modal" phx-key="Escape">
      <div
        class="gm-backdrop-click"
        phx-click="close_modal"
        style="position: absolute; inset: 0; z-index: 0;"
      />
      <div class="gm-dialog" style="position: relative; z-index: 1;">
        <div class="gm-head">
          <div class="gm-title">
            <span :if={@glyph} class="glyph">{@glyph}</span>
            <span>{@title}</span>
          </div>
          <button class="gm-close" phx-click="close_modal" aria-label="Close">✕</button>
        </div>
        <div class="gm-body">
          {render_slot(@inner_block)}
        </div>
        <div :if={@foot_hint} class="gm-foot-hint">
          <span>{@foot_hint}</span>
          <span><span class="kbd">esc</span> to close</span>
        </div>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Stats Modal
  # ────────────────────────────────────────────────────────────

  attr :stats, :map, required: true

  def stats_modal(assigns) do
    assigns = assign(assigns, :ability_scores, GameData.ability_scores())

    ~H"""
    <.modal
      title="Character Sheet"
      glyph="✧"
      foot_hint="Click a stat to invoke — spend mana, rest, meditate."
    >
      <div style="display: grid; grid-template-columns: 200px 1fr; gap: 32px; align-items: start;">
        <div>
          <div class="sigil" style="width: 80px; height: 80px; font-size: 44px;">V</div>
          <div style="margin-top: 14px;">
            <div style="font-family: var(--serif); font-size: 22px; color: var(--ink); font-weight: 500;">
              {@stats.name}
            </div>
            <div style="font-size: 11px; color: var(--ink-faint); text-transform: uppercase; letter-spacing: 0.14em; margin-top: 2px;">
              {@stats.class}
            </div>
          </div>
          <div style="margin-top: 18px; font-size: 12px; color: var(--ink-dim); line-height: 1.7; font-family: var(--prose);">
            Devoted to the Dawnbringer. Bound by oath to protect the pilgrim roads between Ashfall and Hollowvale.
          </div>
        </div>
        <div>
          <div class="big-bar-block">
            <.hp_bar label="Health" cur={@stats.hp.cur} max={@stats.hp.max} kind="hp" />
            <div style="font-size: 11px; color: var(--ink-faint); margin-top: 6px;">
              Regenerates slowly while resting
            </div>
          </div>
          <div class="big-bar-block">
            <.hp_bar label="Mana" cur={@stats.mp.cur} max={@stats.mp.max} kind="mp" />
            <div style="font-size: 11px; color: var(--ink-faint); margin-top: 6px;">
              Channel Dawnlight — 8 mp
            </div>
          </div>
          <div class="big-bar-block">
            <.hp_bar label="Experience" cur={@stats.xp.cur} max={@stats.xp.max} kind="xp" />
            <div style="font-size: 11px; color: var(--ink-faint); margin-top: 6px;">
              560 xp to level 8
            </div>
          </div>
          <div class="stats-grid" style="margin-top: 22px;">
            <div :for={score <- @ability_scores} class="stat-row">
              <span class="k">{score.name}</span>
              <span class="v">{score.value}</span>
              <span class="sub">{score.modifier}</span>
            </div>
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Inventory Modal
  # ────────────────────────────────────────────────────────────

  attr :inventory, :list, required: true

  def inventory_modal(assigns) do
    ~H"""
    <.modal
      title="Inventory"
      glyph="❖"
      foot_hint="Type `drop &lt;name&gt;` in the input to drop an item."
    >
      <div :if={@inventory == []} class="inv-empty" style="color: var(--ink-faint); padding: 12px;">
        You aren't carrying anything.
      </div>
      <div :if={@inventory != []} class="inv-grid">
        <div :for={item <- @inventory} class="inv-tile">
          <div class="nm">{item.name}</div>
          <div class="meta">
            <span>{item.short_description}</span>
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Quest Modal
  # ────────────────────────────────────────────────────────────

  attr :quest_details, :list, required: true
  attr :selected_quest, :integer, required: true

  def quest_modal(assigns) do
    q = Enum.at(assigns.quest_details, assigns.selected_quest)
    assigns = assign(assigns, :q, q)

    ~H"""
    <.modal title="Quest Log" glyph="✦">
      <div class="quest-detail">
        <div class="quest-nav">
          <button
            :for={{quest, idx} <- Enum.with_index(@quest_details)}
            class={[@selected_quest == idx && "active"]}
            phx-click="select_quest"
            phx-value-index={idx}
          >
            <div class="t">{quest.title}</div>
            <div class="s">
              {Enum.count(quest.steps, & &1.done)} / {length(quest.steps)} steps
            </div>
          </button>
        </div>
        <div class="quest-body">
          <h3>{@q.title}</h3>
          <div class="giver">Given by {@q.giver}</div>
          <p style="font-style: italic; color: var(--ink);">{@q.synopsis}</p>
          <p>{@q.desc}</p>
          <div class="quest-steps">
            <div :for={step <- @q.steps} class={["quest-step", step.done && "done"]}>
              <div class="check">{if step.done, do: "✓", else: ""}</div>
              <div class="t">{step.t}</div>
            </div>
          </div>
          <div style="font-size: 10px; color: var(--ink-faint); letter-spacing: 0.12em; text-transform: uppercase; margin-top: 18px;">
            Rewards
          </div>
          <div class="reward-row">
            <span :for={reward <- @q.rewards} class="tag">{reward}</span>
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Presence Modal
  # ────────────────────────────────────────────────────────────

  attr :presence, :list, required: true

  def presence_modal(assigns) do
    ~H"""
    <.modal
      title="Present in Room"
      glyph="◈"
      foot_hint="Other players currently in this room."
    >
      <div :if={@presence == []} style="color: var(--ink-faint); padding: 12px;">
        You are alone here.
      </div>
      <div :if={@presence != []} class="presence-grid">
        <div :for={p <- @presence} class="presence-card other">
          <div class="avatar">{String.first(p.username) |> String.upcase()}</div>
          <div>
            <div class="name">{p.username}</div>
            <div class="role">Player</div>
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Player View
  # ────────────────────────────────────────────────────────────

  attr :log, :list, required: true
  attr :stats, :map, required: true
  attr :inventory, :list, required: true
  attr :quests, :list, required: true
  attr :presence, :list, required: true
  attr :suggestions, :list, required: true
  attr :input, :string, required: true
  attr :streaming, :boolean, required: true
  attr :map_open, :boolean, required: true
  attr :map_view, :map, required: true
  attr :input_locked, :boolean, default: false
  attr :tweaks, :map, required: true

  def player_view(assigns) do
    ~H"""
    <div
      class="player"
      data-layout={@tweaks.player_layout}
      data-hud={if @tweaks.show_hud, do: "shown", else: "hidden"}
      data-map={if @map_open, do: "open", else: "closed"}
    >
      <.mini_map :if={@map_open} map_view={@map_view} />

      <main class="p-log" id="game-log" phx-hook=".ScrollBottom">
        <div class="p-log-inner">
          <.log_entry :for={entry <- @log} entry={entry} />
          <div
            :if={@streaming}
            id="streaming-text"
            phx-hook=".StreamingText"
            class="log-entry narrate"
          >
            <span class="cursor" />
          </div>
        </div>
      </main>

      <.stats_panel
        :if={@tweaks.show_hud}
        stats={@stats}
        inventory={@inventory}
        quests={@quests}
        presence={@presence}
        layout={@tweaks.player_layout}
      />

      <footer class="p-input">
        <div class="p-input-line">
          <button
            class={["map-toggle", @map_open && "open"]}
            phx-click="toggle_map"
            title={if @map_open, do: "Hide map", else: "Show map"}
            aria-label={if @map_open, do: "Hide map", else: "Show map"}
          >
            <svg
              width="16"
              height="16"
              viewBox="0 0 16 16"
              fill="none"
              stroke="currentColor"
              stroke-width="1.3"
              stroke-linejoin="round"
            >
              <path d="M1 3.5 5.5 2l5 1.5L15 2v10.5L10.5 14l-5-1.5L1 14z" />
              <path d="M5.5 2v10.5M10.5 3.5V14" />
            </svg>
          </button>
          <div class="p-input-row">
            <span class="p-input-prompt">›</span>
            <form phx-submit="submit_command" style="display: contents;">
              <input
                name="text"
                value={@input}
                phx-change="update_input"
                autocomplete="off"
                disabled={@input_locked}
                placeholder={
                  if @input_locked,
                    do: "thinking…",
                    else: "what do you do?  try 'read letter', 'whisper sable', or 'inventory'"
                }
              />
              <button type="submit" class="send" disabled={@input_locked}>send ↵</button>
            </form>
          </div>
        </div>
        <div class="suggest-row">
          <span class="suggest-label">suggested</span>
          <button
            :for={s <- @suggestions}
            class="suggest-chip"
            phx-click="click_suggestion"
            phx-value-text={s}
          >
            {s}
          </button>
        </div>
      </footer>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Wizard Field
  # ────────────────────────────────────────────────────────────

  attr :field, :map, required: true
  attr :delay, :integer, default: 0

  def wizard_field(assigns) do
    ~H"""
    <div class="dc-field" style={"animation-delay: #{@delay}ms"}>
      <div class="k">{@field.k}</div>
      <div class={[
        "v",
        @field.kind == "prose" && "prose",
        @field.kind in ~w(tag tags exits entities) && "tag-list"
      ]}>
        <%= case @field.kind do %>
          <% "prose" -> %>
            <span>{@field.v}</span>
          <% "num" -> %>
            <span class="tag num">{@field.v}</span>
          <% "tag" -> %>
            <span :for={t <- String.split(@field.v, ~r/[·,]/)}>
              <span class="tag">{String.trim(t)}</span>
            </span>
          <% "tags" -> %>
            <span :for={t <- @field[:items] || []} class="tag">{t}</span>
          <% "exits" -> %>
            <div :for={exit <- @field[:exits] || []} class="exit-pair" style="width: 100%;">
              <span class="dir">{exit.dir}</span>
              <span class="arrow">→</span>
              <span class="dest">{exit.to}</span>
            </div>
          <% "entities" -> %>
            <span :for={e <- @field[:entities] || []} class="tag">
              {e.name} <span style="opacity: 0.5; margin-left: 4px;">· {e.type}</span>
            </span>
          <% "stats" -> %>
            <div class="dc-stats-grid">
              <div :for={s <- @field[:stats] || []} class="dc-stat">
                <span class="k">{s.k}</span>
                <span class="v">{s.v}</span>
                <span :if={s[:sub]} class="sub">{s.sub}</span>
              </div>
            </div>
          <% "loot" -> %>
            <div class="dc-loot">
              <div :for={item <- @field[:items] || []} class="dc-loot-row">
                <span class="nm">{item.name}</span>
                <span class="chance">{item.chance}%</span>
              </div>
            </div>
          <% "adjectives" -> %>
            <div class="dc-adj">
              <div class="dc-adj-chips">
                <span :for={a <- @field[:items] || []} class="dc-adj-chip">
                  {a}<span class="x">×</span>
                </span>
                <span class="dc-adj-add">+ add</span>
              </div>
              <div :if={@field[:note]} class="dc-adj-note">{@field.note}</div>
            </div>
          <% "steps" -> %>
            <div class="dc-steps">
              <div :for={{s, idx} <- Enum.with_index(@field[:steps] || [])} class="dc-step-row">
                <span class="num">{idx + 1}</span>
                <div class="body">
                  <div class="id">{s.id}</div>
                  <div class="desc">{s.desc}</div>
                </div>
              </div>
            </div>
          <% "rewards" -> %>
            <div class="dc-rewards">
              <div :for={r <- @field[:rewards] || []} class="dc-reward-row">
                <span class={"rw-kind #{r.kind}"}>{r.kind}</span>
                <span class="rw-val">
                  {r.value}
                  <span :if={r[:label]} class="rw-label">{r.label}</span>
                </span>
              </div>
            </div>
          <% _ -> %>
            <span>{@field[:v]}</span>
        <% end %>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Data Card
  # ────────────────────────────────────────────────────────────

  attr :example, :map, required: true
  attr :visible_field_count, :integer, required: true

  def data_card(assigns) do
    visible_fields = Enum.take(assigns.example.fields, assigns.visible_field_count)
    assigns = assign(assigns, :visible_fields, visible_fields)

    ~H"""
    <div class="data-card">
      <div class="dc-header">
        <div class="icon">{@example.icon}</div>
        <div class="ids">
          <div class="dc-title">{@example.title}</div>
          <div class="dc-slug">{@example.slug}</div>
        </div>
        <div class="dc-status">draft · unsaved</div>
      </div>
      <.wizard_field
        :for={{field, idx} <- Enum.with_index(@visible_fields)}
        field={field}
        delay={idx * 60}
      />
      <.trigger_section
        :if={(@example[:triggers] || []) != []}
        triggers={@example.triggers}
      />
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Trigger Components
  # ────────────────────────────────────────────────────────────

  attr :triggers, :list, required: true

  def trigger_section(assigns) do
    ~H"""
    <div class="trigger-section">
      <div class="trigger-section-head">Triggers</div>
      <div class="trigger-flow">
        <div
          :for={{trg, idx} <- Enum.with_index(@triggers)}
          style={"animation: fadeIn 300ms ease #{idx * 120 + 300}ms both"}
        >
          <.trigger_compact_card trigger={trg} />
        </div>
        <button class="add-trigger-btn">+ add trigger</button>
      </div>
    </div>
    """
  end

  attr :trigger, :map, required: true

  def trigger_compact_card(assigns) do
    ~H"""
    <div
      class="trigger-card"
      phx-click="open_trigger"
      phx-value-id={@trigger.id}
      role="button"
      tabindex="0"
    >
      <div class="trigger-card-compact">
        <span class="token intent">
          <span class="lbl">intent</span>
          {@trigger.intent}
        </span>
        <span class="act-count">
          {length(@trigger.actions)} action{if length(@trigger.actions) == 1, do: "", else: "s"}
        </span>
        <span class="chev">›</span>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Conditions Editor
  # ────────────────────────────────────────────────────────────

  attr :conditions, :list, required: true

  def conditions_editor(assigns) do
    ops = GameData.condition_ops()
    assigns = assign(assigns, :ops, ops)

    ~H"""
    <div class="cond-list">
      <div :if={@conditions == []} class="cond-empty">
        No conditions — trigger fires on every matching intent.
      </div>
      <div :for={{c, idx} <- Enum.with_index(@conditions)} class="cond-row">
        <span class="cond-num">{idx + 1}</span>
        <span class="cond-subject">{c.subject}</span>
        <span class="cond-op">{@ops[c.op] || c.op}</span>
        <span class="cond-value">
          {if is_binary(c.value), do: "\"#{c.value}\"", else: to_string(c.value)}
        </span>
        <button class="cond-remove" aria-label="Remove">✕</button>
      </div>
      <button class="trg-add-action">+ add condition</button>
      <div class="cond-hint">
        All conditions must evaluate to true at the moment the matching intent fires.
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Action Row
  # ────────────────────────────────────────────────────────────

  attr :index, :integer, required: true
  attr :action, :map, required: true

  def action_row(assigns) do
    labels = GameData.action_labels()
    kind_label = labels[assigns.action.kind] || assigns.action.kind
    assigns = assign(assigns, :kind_label, kind_label)

    ~H"""
    <div class="action-row">
      <div class="step">{@index}</div>
      <div class="kind-pill">{@kind_label}</div>
      <div class="action-body">
        <%= case @action.kind do %>
          <% "emit_text" -> %>
            <span class="arg">to {@action.scope}</span>
            <span class="literal">&ldquo;{@action.text}&rdquo;</span>
          <% "modify_prop" -> %>
            <span class="tgt">{@action.target}</span>
            <span class="arg" style="margin-left: 8px;">set</span>
            <span class="arg">{@action.prop}</span>
            <span class="val">= {@action.value}</span>
          <% "spawn_entity" -> %>
            <span class="tgt">{@action.target}</span>
            <span class="arg" style="margin-left: 8px;">attrs</span>
            <span class="val">{@action.attrs}</span>
          <% "set_disposition" -> %>
            <span class="tgt">{@action.target}</span>
            <span class="arg" style="margin-left: 8px;">to</span>
            <span class="val">{@action.value}</span>
          <% "grant_item" -> %>
            <span class="tgt">{@action.target}</span>
            <span class="arg" style="margin-left: 8px;">item</span>
            <span class="val">{@action.value}</span>
          <% "require_input" -> %>
            <span class="tgt">{@action.target}</span>
            <span class="arg" style="margin-left: 8px;">prompt</span>
            <span class="literal">&ldquo;{@action.prompt}&rdquo;</span>
          <% _ -> %>
            <span class="val">{inspect(@action)}</span>
        <% end %>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Trigger Modal
  # ────────────────────────────────────────────────────────────

  attr :trigger, :map, required: true

  def trigger_modal(assigns) do
    intents = GameData.trigger_intents()
    assigns = assign(assigns, :intents, intents)

    ~H"""
    <div class="gm-backdrop" phx-window-keydown="close_trigger" phx-key="Escape">
      <div
        class="gm-backdrop-click"
        phx-click="close_trigger"
        style="position: absolute; inset: 0; z-index: 0;"
      />
      <div class="gm-dialog" style="position: relative; z-index: 1;">
        <div class="trg-modal-head">
          <div style="display: flex; justify-content: space-between; align-items: center;">
            <div style="font-size: 10px; text-transform: uppercase; letter-spacing: 0.14em; color: var(--wizard); font-weight: 600;">
              ✦ Trigger
            </div>
            <button class="gm-close" phx-click="close_trigger">✕</button>
          </div>
          <div class="trigger-chain">
            <span class="token intent">
              <span class="lbl">intent</span>{@trigger.intent}
            </span>
          </div>
          <div class="trg-id">{@trigger.id}</div>
        </div>

        <div class="gm-body" style="padding: 0;">
          <div class="trg-modal-section">
            <h4>Matching</h4>
            <div class="trg-field">
              <div>
                <label>Intent</label>
                <select>
                  <option :for={intent <- @intents} selected={intent == @trigger.intent}>
                    {intent}
                  </option>
                </select>
              </div>
            </div>
          </div>

          <div class="trg-modal-section">
            <h4>
              Conditions ·
              <span style="color: var(--ink-faint); font-weight: 400; text-transform: none; letter-spacing: 0;">
                all must be true
              </span>
            </h4>
            <.conditions_editor conditions={@trigger[:conditions] || []} />
          </div>

          <div class="trg-modal-section">
            <h4>Note</h4>
            <div style="font-family: var(--prose); font-size: 14px; color: var(--ink-dim); font-style: italic; line-height: 1.6;">
              {@trigger.note}
            </div>
          </div>

          <div class="trg-modal-section">
            <h4>Actions · in order</h4>
            <div style="display: flex; flex-direction: column; gap: 4px;">
              <.action_row
                :for={{action, idx} <- Enum.with_index(@trigger.actions)}
                index={idx + 1}
                action={action}
              />
            </div>
            <button class="trg-add-action">+ add action</button>
          </div>

          <div
            class="trg-modal-section"
            style="display: flex; justify-content: space-between; align-items: center;"
          >
            <div style="font-size: 10px; color: var(--ink-faint); letter-spacing: 0.1em; text-transform: uppercase;">
              Fires ~ 0 times so far · never played
            </div>
            <div style="display: flex; gap: 8px;">
              <button class="btn-ghost">Duplicate</button>
              <button class="btn-ghost" style="color: var(--danger); border-color: var(--danger);">
                Delete
              </button>
              <button class="btn-primary">Save trigger</button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Kind Picker
  # ────────────────────────────────────────────────────────────

  attr :value, :atom, required: true

  def kind_picker(assigns) do
    kinds = [
      %{id: :room, label: "Room"},
      %{id: :npc, label: "NPC"},
      %{id: :item, label: "Item"},
      %{id: :quest, label: "Quest"},
      %{id: :spell, label: "Spell"}
    ]

    assigns = assign(assigns, :kinds, kinds)

    ~H"""
    <div class="w-kind-picker">
      <button
        :for={k <- @kinds}
        class={["kind-chip", @value == k.id && "active"]}
        phx-click="set_wizard_kind"
        phx-value-kind={k.id}
      >
        {k.label}
      </button>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Wizard View
  # ────────────────────────────────────────────────────────────

  attr :kind, :atom, required: true
  attr :text, :string, required: true
  attr :tweaks, :map, required: true
  attr :wizard_examples, :map, required: true

  def wizard_view(assigns) do
    example = assigns.wizard_examples[assigns.kind] || assigns.wizard_examples[:room]
    chars = String.trim(assigns.text) |> String.length()
    total_fields = length(example.fields)
    visible_count = min(total_fields, max(2, div(chars, 20)))
    is_empty = chars < 20

    word_count =
      assigns.text
      |> String.trim()
      |> String.split(~r/\s+/)
      |> Enum.reject(&(&1 == ""))
      |> length()

    token_estimate = ceil(word_count * 1.3)

    assigns =
      assigns
      |> assign(:example, example)
      |> assign(:is_empty, is_empty)
      |> assign(:word_count, word_count)
      |> assign(:token_estimate, token_estimate)
      |> assign(:visible_count, visible_count)

    ~H"""
    <div class="wizard">
      <div class="w-left">
        <div class="w-head">
          <div>
            <div class="lbl">Wizard mode · creator</div>
            <div class="title">Describing a <b>{String.downcase(@example.kind)}</b></div>
          </div>
          <div style="font-size: 11px; color: var(--ink-faint); letter-spacing: 0.08em;">
            ⌘S save · ⌘P preview
          </div>
        </div>

        <div class="w-input-wrap">
          <.kind_picker value={@kind} />
          <div class="w-prompt-label">
            <span class="hint">
              Describe what you want to create in plain language — the model interprets it into structured data on the right.
            </span>
          </div>
          <form phx-change="update_wizard_text" style="display: contents;">
            <textarea
              name="text"
              class="w-input"
              placeholder={"Describe a #{@kind} in natural language..."}
              spellcheck="false"
            >{@text}</textarea>
          </form>
          <div style="font-size: 11px; color: var(--ink-faint); display: flex; gap: 18px;">
            <span>{@word_count} words</span>
            <span>~{@token_estimate} tokens</span>
            <span style="margin-left: auto;">ready</span>
          </div>
        </div>

        <div class="w-footer">
          <div class="meta">
            <span class="pulse">live · gpt-realm-1</span>
            <span>rev 12</span>
          </div>
          <div class="actions">
            <button class="btn-ghost">Discard</button>
            <button class="btn-ghost">Save as draft</button>
            <button class="btn-primary">Commit to world ✦</button>
          </div>
        </div>
      </div>

      <div class="w-right">
        <section class="w-pane">
          <div class="w-pane-head">
            <div class="lbl">Interpreted data</div>
          </div>
          <div class="w-pane-body">
            <%= if @is_empty do %>
              <div class="empty-preview">
                <div>
                  <div class="title">Nothing conjured yet</div>
                  <div>
                    Begin describing a {@kind} on the left.<br />
                    The system will crystallize structure as you write.
                  </div>
                </div>
              </div>
            <% else %>
              <.data_card example={@example} visible_field_count={@visible_count} />
            <% end %>
          </div>
        </section>

        <%= if @kind != :quest do %>
          <section class="w-pane">
            <div class="w-pane-head">
              <div class="lbl">
                <span style="width: 6px; height: 6px; border-radius: 50%; background: var(--player); display: inline-block; box-shadow: 0 0 6px var(--player);" />
                As player would see it
              </div>
              <div style="font-size: 10px; color: var(--ink-faint); letter-spacing: 0.08em; text-transform: uppercase;">
                hypothetical · not saved
              </div>
            </div>
            <div class="w-pane-body">
              <%= if @is_empty do %>
                <div class="empty-preview">
                  <div>
                    <div class="title">Nothing conjured yet</div>
                    <div>
                      Begin describing a place on the left.<br />
                      The system will crystallize structure as you write.
                    </div>
                  </div>
                </div>
              <% else %>
                <div style="max-width: 640px;">
                  <div
                    class="log-entry room"
                    style="border-top: 0; margin-top: 0; padding-top: 0;"
                  >
                    {raw(@example[:ingame] || "")}
                  </div>
                  <div class="log-entry system">
                    A hush falls. The candles flicker blue.
                  </div>
                  <div class="log-entry cmd">look astrolabe</div>
                  <div class="log-entry narrate">
                    Brass, tarnished, etched with stars you do not recognize. It hums faintly beneath your fingers.<span class="cursor" />
                  </div>
                </div>
              <% end %>
            </div>
          </section>
        <% end %>
      </div>
    </div>
    """
  end
end
