defmodule AgenticRealmsWeb.GameComponents.PlayerView do
  @moduledoc """
  The main player surface: scroll-anchored log, optional mini-map,
  stats sidebar, and the command input row with the map toggle.

  Auto-scroll-to-bottom is achieved by giving `.p-log` a
  `flex-direction: column-reverse` in CSS. Source order is newest-first
  (we `Enum.reverse(@log)` here so the in-memory append-at-end shape is
  unchanged); the browser flips them visually so the newest entry sits
  at the bottom and the scroll anchors to the flex "start" — which is
  visually the bottom. No JS, no race conditions; when `@log` grows the
  visible bottom updates instantly, and when the user scrolls up the
  browser preserves their position.
  """

  use AgenticRealmsWeb, :html

  import AgenticRealmsWeb.GameComponents.Primitives, only: [stats_panel: 1]
  import AgenticRealmsWeb.GameComponents.MiniMap, only: [mini_map: 1]
  import AgenticRealmsWeb.GameComponents.LogEntry, only: [log_entry: 1]

  attr :log, :list, required: true
  attr :stats, :map, required: true
  attr :inventory, :list, required: true
  attr :quests, :list, required: true
  attr :presence, :list, required: true
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

      <main class="p-log" id="game-log">
        <div
          :if={@streaming}
          id="streaming-text"
          phx-hook=".StreamingText"
          class="log-entry narrate"
        >
          <span class="cursor" />
        </div>
        <.log_entry :for={entry <- Enum.reverse(@log)} entry={entry} />
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
      </footer>
    </div>
    """
  end
end
