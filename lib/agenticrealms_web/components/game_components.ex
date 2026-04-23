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

  def log_entry(%{entry: %{kind: :narrate}} = assigns) do
    ~H"""
    <div class="log-entry narrate">{@entry.text}</div>
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
        <.hud_card title="Inventory" count={"#{length(@inventory)} / 16"} modal_type="inv">
          <div class="inv-list">
            <div
              :for={item <- Enum.take(@inventory, 5)}
              class={["row", item.equipped && "equipped"]}
            >
              <span>{item.name}</span>
              <span :if={item.qty > 1} class="qty">×{item.qty}</span>
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
          <div :for={p <- @presence} class="presence-row">
            <span class={["presence-dot", p.status == "idle" && "idle"]} />
            <span>{p.name}{if p.npc, do: " (innkeep)", else: ""}</span>
            <span style="margin-left: auto; font-size: 10px; color: var(--ink-ghost);">
              {p.status}
            </span>
          </div>
        </.hud_card>
      <% end %>
    </aside>
    """
  end

  # ────────────────────────────────────────────────────────────
  # Mini Map
  # ────────────────────────────────────────────────────────────

  def mini_map(assigns) do
    nodes = GameData.map_nodes()
    edges = GameData.map_edges()
    by_id = Map.new(nodes, fn n -> {n.id, n} end)
    assigns = assign(assigns, nodes: nodes, edges: edges, by_id: by_id)

    ~H"""
    <div class="stat-block">
      <h4>Region · Blackvane</h4>
      <div class="map">
        <div class="map-grid"></div>
        <%= for {a_id, b_id} <- @edges do %>
          <% a = @by_id[a_id] %>
          <% b = @by_id[b_id] %>
          <% dx = b.x - a.x %>
          <% dy = b.y - a.y %>
          <% len = :math.sqrt(dx * dx + dy * dy) %>
          <% ang = :math.atan2(dy, dx) * 180 / :math.pi() %>
          <div
            class="map-edge"
            style={"left: #{a.x}%; top: #{a.y}%; width: #{len}%; transform: rotate(#{ang}deg)"}
          >
          </div>
        <% end %>
        <div
          :for={node <- @nodes}
          class={"map-node #{node.state}"}
          style={"left: #{node.x}%; top: #{node.y}%"}
          title={node.label}
        >
        </div>
      </div>
      <div style="margin-top: 12px;">
        <div class="dir-pad">
          <span /><button>N</button> <span />
          <button>W</button><button disabled>·</button><button>E</button>
          <span /><button>S</button> <span />
        </div>
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
      foot_hint="Click an item to examine, use, or drop."
    >
      <div class="inv-filter">
        <input placeholder="filter items..." />
        <span class="cap">{length(@inventory)} / 16 · 12.4 lbs</span>
      </div>
      <div class="inv-grid">
        <div :for={item <- @inventory} class={["inv-tile", item.equipped && "equipped"]}>
          <div class="nm">{item.name}</div>
          <div class="meta">
            <span>{if item.equipped, do: "worn", else: "carried"}</span>
            <span class="qty-badge">×{item.qty}</span>
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
    roles = GameData.presence_roles()
    assigns = assign(assigns, :roles, roles)

    ~H"""
    <.modal
      title="Present in Room"
      glyph="◈"
      foot_hint="Whisper, trade, party up, or inspect — all from here."
    >
      <div class="presence-grid">
        <div
          :for={p <- @presence}
          class={"presence-card #{(@roles[p.name] || %{kind: "other"}).kind}"}
        >
          <div class="avatar">{String.first(p.name)}</div>
          <div>
            <div class="name">{p.name}</div>
            <div class="role">
              {(@roles[p.name] || %{role: if(p.npc, do: "NPC", else: "Player")}).role} · {p.status}
            </div>
          </div>
          <div class="actions">
            <button>whisper</button>
            <button>inspect</button>
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
  attr :tweaks, :map, required: true

  def player_view(assigns) do
    ~H"""
    <div
      class="player"
      data-layout={@tweaks.player_layout}
      data-hud={if @tweaks.show_hud, do: "shown", else: "hidden"}
      data-map={if @map_open, do: "open", else: "closed"}
    >
      <aside :if={@map_open} class="p-side-left">
        <.mini_map />
      </aside>

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
                placeholder="what do you do?  try 'read letter', 'whisper sable', or 'inventory'"
              />
              <button type="submit" class="send">send ↵</button>
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
