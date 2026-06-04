defmodule AgenticRealmsWeb.GameComponents.Primitives do
  @moduledoc """
  Shared low-level UI primitives used by both player and wizard views:
  HP/MP/XP progress bars, collapsible HUD cards, the modal shell, the
  player-sidebar stats panel, and the directional-arrow glyph helper.
  """

  use AgenticRealmsWeb, :html

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
  # Stats Panel — the player sidebar with Character / Inventory /
  # Quest Log / Present HUD cards.
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
          <div :if={@quests == []} style="font-size: 11px; color: var(--ink-faint);">
            (no active quests)
          </div>
          <div
            :for={{quest, idx} <- Enum.with_index(@quests)}
            class="quest-item"
            style={if idx == length(@quests) - 1, do: "margin-bottom: 0;", else: ""}
          >
            <div class="qt">{quest.title}</div>
            <div :for={c <- quest.criteria} class="qp">
              {c.name}: {c.count} / {c.target}
            </div>
          </div>
        </.hud_card>

        <.hud_card title="Present" count={"#{length(@presence)} here"} modal_type="presence">
          <div :if={@presence == []} style="font-size: 11px; color: var(--ink-faint);">
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
  # Direction arrow glyph — used by log entries (room view exits)
  # and by any future component that wants a compact directional
  # indicator. Accepts either the canonical atom (`:north`,
  # `:northeast`, …) or its lowercase string form. Up and north
  # both render as ↑; down and south as ↓.
  # ────────────────────────────────────────────────────────────

  @arrow_by_dir %{
    "north" => "↑",
    "south" => "↓",
    "east" => "→",
    "west" => "←",
    "northeast" => "↗",
    "northwest" => "↖",
    "southeast" => "↘",
    "southwest" => "↙",
    "up" => "↑",
    "down" => "↓"
  }

  @doc false
  def direction_arrow(dir) when is_atom(dir),
    do: Map.get(@arrow_by_dir, Atom.to_string(dir), "·")

  def direction_arrow(dir) when is_binary(dir),
    do: Map.get(@arrow_by_dir, String.downcase(dir), "·")

  def direction_arrow(_), do: "·"
end
