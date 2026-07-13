defmodule AgenticRealmsWeb.GameComponents.PlayerModals do
  @moduledoc """
  The four player-facing modal surfaces wired to the HUD cards in the
  player sidebar: Character (stats), Inventory, Quest Log, Present in
  Room. Each one wraps the shared `<.modal>` shell from Primitives.
  """

  use AgenticRealmsWeb, :html

  import AgenticRealmsWeb.GameComponents.Primitives, only: [modal: 1, hp_bar: 1]

  # ────────────────────────────────────────────────────────────
  # Stats Modal
  # ────────────────────────────────────────────────────────────

  attr :stats, :map, required: true

  def stats_modal(assigns) do
    ~H"""
    <.modal title="Character Sheet" glyph="✧">
      <div style="display: grid; grid-template-columns: 200px 1fr; gap: 32px; align-items: start;">
        <div>
          <div class="sigil" style="width: 80px; height: 80px; font-size: 44px;">
            {String.upcase(String.first(@stats.name))}
          </div>
          <div style="margin-top: 14px;">
            <div style="font-family: var(--serif); font-size: 22px; color: var(--ink); font-weight: 500;">
              {@stats.name}
            </div>
            <div style="font-size: 11px; color: var(--ink-faint); text-transform: uppercase; letter-spacing: 0.14em; margin-top: 2px;">
              {"Level #{@stats.level}"}
            </div>
          </div>
        </div>
        <div>
          <div class="big-bar-block">
            <.hp_bar label="Health" cur={@stats.hp.cur} max={@stats.hp.max} kind="hp" />
          </div>
          <div class="big-bar-block">
            <.hp_bar label="Mana" cur={@stats.mana.cur} max={@stats.mana.max} kind="mp" />
          </div>
          <div class="big-bar-block">
            <.hp_bar label="Experience" cur={@stats.xp.into_level} max={@stats.xp.to_next} kind="xp" />
            <div style="font-size: 11px; color: var(--ink-faint); margin-top: 6px;">
              {@stats.xp.to_next - @stats.xp.into_level} xp to level {@stats.level + 1}
            </div>
          </div>
          <div class="stats-grid" style="margin-top: 22px;">
            <div :for={score <- @stats.abilities} class="stat-row">
              <span class="k">{score.name}</span>
              <span class="v">{score.value}</span>
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
  # Quest Modal (feature 013)
  # ────────────────────────────────────────────────────────────
  #
  # Active section: every active quest with per-criterion progress
  # lines. Completed section: every completed quest with title, reward
  # name, and completion timestamp.

  attr :quests, :list, required: true
  attr :completed_quests, :list, required: true

  def quest_modal(assigns) do
    ~H"""
    <.modal title="Quest Log" glyph="✦">
      <div class="quest-log">
        <div class="quest-section">
          <div class="quest-section-title">Active ({length(@quests)})</div>
          <div :if={@quests == []} class="quest-empty">No active quests.</div>
          <div :for={quest <- @quests} class="quest-item">
            <div class="qt">{quest.title}</div>
            <div :if={quest[:narrative]} class="qn">{quest.narrative}</div>
            <div :for={c <- quest.criteria} class="qp">
              {c.name}: {c.count} / {c.target}
            </div>
          </div>
        </div>

        <div class="quest-section">
          <div class="quest-section-title">Completed ({length(@completed_quests)})</div>
          <div :if={@completed_quests == []} class="quest-empty">
            No completed quests yet.
          </div>
          <div
            :for={quest <- @completed_quests}
            class="quest-item quest-item--completed"
          >
            <div class="qt">✓ {quest.title}</div>
            <div :if={quest[:reward_name]} class="qp">
              Reward: {quest.reward_name}
            </div>
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
end
