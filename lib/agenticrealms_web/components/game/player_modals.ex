defmodule AgenticRealmsWeb.GameComponents.PlayerModals do
  @moduledoc """
  The four player-facing modal surfaces wired to the HUD cards in the
  player sidebar: Character (stats), Inventory, Quest Log, and Here (who
  else is in the room). Each one wraps the shared `<.modal>` shell from
  Primitives.
  """

  use AgenticRealmsWeb, :html

  import AgenticRealmsWeb.GameComponents.Primitives,
    only: [modal: 1, hp_bar: 1, xp_bar: 1, signed: 1, descriptor: 1]

  alias Phoenix.LiveView.JS

  attr :stats, :map, required: true

  @doc """
  The character sheet: three tabs over the viewing player's own character.

  Tab switching is client-side. Which tab is showing is not authoritative, not
  persisted, and not broadcast, so sending it to the server would buy nothing —
  all three panels render into the DOM and `JS.show/JS.hide` swaps them
  (Principle III). Reopening the sheet therefore always lands on Main, because
  the modal is unmounted on close.
  """
  def stats_modal(assigns) do
    ~H"""
    <.modal title="Character Sheet" glyph="✧">
      <div class="sheet-head">
        <div class="sigil sheet-sigil">
          {String.upcase(String.first(@stats.name))}
        </div>
        <div>
          <div class="sheet-name">{@stats.name}</div>
          <div class="sheet-descriptor">{descriptor(@stats)}</div>
        </div>
      </div>

      <div class="sheet-tabs" role="tablist" aria-label="Character sheet sections">
        <.sheet_tab tab="main" label="Main Stats" selected />
        <.sheet_tab tab="abilities" label="Abilities" />
        <.sheet_tab tab="spells" label="Spells" />
      </div>

      <div id="sheet-panel-main" role="tabpanel" aria-labelledby="sheet-tab-main">
        <.main_panel stats={@stats} />
      </div>

      <div
        id="sheet-panel-abilities"
        role="tabpanel"
        aria-labelledby="sheet-tab-abilities"
        style="display: none;"
      >
        <.abilities_panel stats={@stats} />
      </div>

      <div
        id="sheet-panel-spells"
        role="tabpanel"
        aria-labelledby="sheet-tab-spells"
        style="display: none;"
      >
        <.spells_panel />
      </div>
    </.modal>
    """
  end

  attr :tab, :string, required: true
  attr :label, :string, required: true
  attr :selected, :boolean, default: false

  defp sheet_tab(assigns) do
    ~H"""
    <button
      id={"sheet-tab-#{@tab}"}
      class={["sheet-tab", @selected && "active"]}
      type="button"
      role="tab"
      aria-selected={to_string(@selected)}
      aria-controls={"sheet-panel-#{@tab}"}
      phx-click={select_tab(@tab)}
    >
      {@label}
    </button>
    """
  end

  defp select_tab(tab) do
    Enum.reduce(~w(main abilities spells), %JS{}, fn other, js ->
      if other == tab do
        js
        |> JS.show(to: "#sheet-panel-#{other}")
        |> JS.add_class("active", to: "#sheet-tab-#{other}")
        |> JS.set_attribute({"aria-selected", "true"}, to: "#sheet-tab-#{other}")
      else
        js
        |> JS.hide(to: "#sheet-panel-#{other}")
        |> JS.remove_class("active", to: "#sheet-tab-#{other}")
        |> JS.set_attribute({"aria-selected", "false"}, to: "#sheet-tab-#{other}")
      end
    end)
  end

  attr :stats, :map, required: true

  @doc """
  The sheet's main tab: vitals, identity, and the derived combat values.

  Public because feature 021's creation review renders it too. The review shows
  the character that is about to exist, and showing it through anything other
  than the sheet's own components would let the two drift.
  """
  def main_panel(assigns) do
    ~H"""
    <div class="big-bar-block">
      <.hp_bar label="Health" cur={@stats.hp.cur} max={@stats.hp.max} kind="hp" />
    </div>
    <div class="big-bar-block">
      <.xp_bar xp={@stats.xp} />
      <div class="sheet-xp-caption">
        <%= if @stats.xp.maxed? do %>
          Fully levelled
        <% else %>
          {@stats.xp.to_next - @stats.xp.into_level} xp to level {@stats.level + 1}
        <% end %>
      </div>
    </div>

    <div class="stats-grid sheet-details">
      <.detail k="Armor Class" v={@stats.armor_class} />
      <.detail k="Movement" v={"#{@stats.speed} ft."} />
      <.detail k="Initiative" v={signed(@stats.initiative)} />
      <.detail k="Size" v={String.capitalize(to_string(@stats.size))} />
      <.detail k="Proficiency" v={signed(@stats.proficiency_bonus)} />
      <.detail k="Hit Dice" v={"#{@stats.hit_dice.count}d#{@stats.hit_dice.sides}"} />
      <.detail k="Passive Perception" v={@stats.passive_perception} />
      <.detail k="Background" v={@stats.background && @stats.background.name} />
    </div>
    """
  end

  attr :k, :string, required: true
  attr :v, :any, required: true

  defp detail(assigns) do
    ~H"""
    <div class="stat-row">
      <span class="k">{@k}</span>
      <span class="v">{@v}</span>
    </div>
    """
  end

  attr :stats, :map, required: true

  @doc """
  The sheet's abilities tab: the six scores, saving throws, and every skill.

  Public for the same reason as `main_panel/1`.
  """
  def abilities_panel(assigns) do
    ~H"""
    <div class="sheet-section">
      <div class="sheet-section-title">Ability Scores</div>
      <div class="stats-grid">
        <div :for={a <- @stats.abilities} class="stat-row">
          <span class="k">{a.name}</span>
          <span class="v">{a.score}</span>
          <span class="sub">{signed(a.modifier)}</span>
        </div>
      </div>
    </div>

    <div class="sheet-section">
      <div class="sheet-section-title">Saving Throws</div>
      <div class="stats-grid">
        <div :for={sv <- @stats.saves} class="stat-row">
          <span class="k">{sv.name}</span>
          <span class="v">{signed(sv.modifier)}</span>
          <.proficiency_mark proficient?={sv.proficient?} what={"#{sv.name} saving throw"} />
        </div>
      </div>
    </div>

    <div class="sheet-section">
      <div class="sheet-section-title">Skills</div>
      <div class="stats-grid">
        <div :for={sk <- @stats.skills} class="stat-row">
          <span class="k">{sk.name}</span>
          <span class="v">{signed(sk.modifier)}</span>
          <.proficiency_mark proficient?={sk.proficient?} what={sk.name} />
        </div>
      </div>
    </div>
    """
  end

  attr :proficient?, :boolean, required: true
  attr :what, :string, required: true

  defp proficiency_mark(assigns) do
    ~H"""
    <span
      class={["prof-mark", @proficient? && "on"]}
      aria-label={"#{@what}: #{if @proficient?, do: "proficient", else: "not proficient"}"}
    >
      {if @proficient?, do: "●", else: "○"}
    </span>
    """
  end

  defp spells_panel(assigns) do
    ~H"""
    <div class="sheet-empty">
      Spellcasting is not yet available.
    </div>
    """
  end

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

  attr :presence, :list, required: true

  def presence_modal(assigns) do
    ~H"""
    <.modal
      title="Here"
      glyph="◈"
      foot_hint="Other players currently in this room."
    >
      <div :if={@presence == []} style="color: var(--ink-faint); padding: 12px;">
        You are alone here.
      </div>
      <div :if={@presence != []} class="presence-grid">
        <div :for={p <- @presence} class="presence-card other">
          <div class="avatar">{String.first(p.name) |> String.upcase()}</div>
          <div>
            <div class="name">{p.name}</div>
            <div class="role">Player</div>
          </div>
        </div>
      </div>
    </.modal>
    """
  end
end
