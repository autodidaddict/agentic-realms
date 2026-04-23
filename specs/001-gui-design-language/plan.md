# Implementation Plan: GUI Design Language

**Branch**: `001-gui-design-language` | **Date**: 2026-04-22 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `specs/001-gui-design-language/spec.md`

## Summary

Implement the UI foundation for Agentic Realms as Phoenix LiveView controls with a "terminal revival" design aesthetic. Two core views — Player (narrative log, HUD cards, map, command input) and Wizard (NL prompt, interpreted data card, in-game preview, trigger editor) — share a single LiveView with mode switching. All data is mocked in Elixir modules. CSS from the design prototype is adapted for Tailwind v4 compatibility with custom properties for three themes (phosphor/paper/dusk).

**User constraints**:
- No client-side frameworks (no React, no Vue)
- Every component is a LiveView function component in HEEx templates
- Mock data in Elixir view modules, not in templates
- CSS compatible with Phoenix Tailwind pipeline

## Technical Context

**Language/Version**: Elixir 1.15+ / Erlang OTP 26+  
**Primary Dependencies**: Phoenix 1.8.5, Phoenix LiveView 1.1.0, Tailwind CSS 4.1.12, esbuild 0.25.4  
**Storage**: N/A (all data mocked, no database for this feature)  
**Testing**: ExUnit + Phoenix.LiveViewTest + LazyHTML  
**Target Platform**: Web browser (desktop only, no mobile)  
**Project Type**: Web application (Phoenix LiveView)  
**Performance Goals**: Sub-200ms modal opens, streaming text completes in <3s  
**Constraints**: No external CDN links, no inline `<script>` tags, no daisyUI in game views, fonts self-hosted  
**Scale/Scope**: 2 views, ~15 function components, ~2200 lines of custom CSS, 1 LiveView

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution is a template (not yet ratified for this project). No gates to enforce. Proceeding.

**Post-Phase 1 re-check**: No violations. The design uses function components (simple), a single LiveView (minimal routing), and mocked data (no ORM/repository patterns).

## Project Structure

### Documentation (this feature)

```text
specs/001-gui-design-language/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: technical decisions
├── data-model.md        # Phase 1: entity definitions
├── quickstart.md        # Phase 1: setup guide
├── contracts/
│   └── ui-components.md # Phase 1: component API contracts
└── checklists/
    └── requirements.md  # Specification quality checklist
```

### Source Code (repository root)

```text
lib/
├── agenticrealms/
│   ├── application.ex          # existing
│   ├── repo.ex                 # existing
│   └── game_data.ex            # NEW: mock data module
└── agenticrealms_web/
    ├── components/
    │   ├── core_components.ex  # existing (untouched)
    │   ├── game_components.ex  # NEW: all game UI function components
    │   └── layouts.ex          # MODIFIED: custom app layout for game
    │   └── layouts/
    │       └── root.html.heex  # MODIFIED: font loading, theme setup
    ├── live/
    │   └── game_live.ex        # NEW: main LiveView (mount, events)
    │   └── game_live.html.heex # NEW: main template
    ├── router.ex               # MODIFIED: add live route
    └── agenticrealms_web.ex    # MODIFIED: import GameComponents

assets/
├── css/
│   ├── app.css                 # MODIFIED: import game.css
│   └── game.css                # NEW: game design system (~2200 lines)
└── js/
    └── app.js                  # existing (colocated hooks auto-registered)

priv/
└── static/
    └── fonts/                  # NEW: self-hosted web fonts
        ├── jetbrains-mono/     # JetBrains Mono (regular, 600, 700)
        ├── ibm-plex-mono/      # IBM Plex Mono (regular, italic)
        └── fraunces/           # Fraunces (variable or 400, 500, 600)

test/
└── agenticrealms_web/
    └── live/
        └── game_live_test.exs  # NEW: LiveView tests
```

**Structure Decision**: Standard Phoenix web application structure. The game feature adds one LiveView, one components module, one data module, and custom CSS. No structural changes to the project layout.

## Implementation Phases

### Phase A: Foundation (CSS + Fonts + Data)

**Goal**: Establish the design system and mock data so components can be built against them.

1. **Download and install web fonts** into `priv/static/fonts/`
   - JetBrains Mono: Regular (400), SemiBold (600), Bold (700)
   - IBM Plex Mono: Regular (400), Italic (400i)
   - Fraunces: Variable or Regular (400), Medium (500), SemiBold (600)
   - Add `@font-face` declarations to `assets/css/game.css`

2. **Create `assets/css/game.css`** with the complete design system:
   - CSS custom properties (`:root` for phosphor theme)
   - Theme variants (`[data-theme="paper"]`, `[data-theme="dusk"]`)
   - Density variant (`[data-density="compact"]`)
   - Layout styles for app shell, player view, wizard view
   - Component styles for log entries, HUD cards, modals, triggers, data cards
   - Animation keyframes (fadeIn, blink, flash, pulse, slideModal, fadeModal)
   - Translate all `oklch()` colors from the design prototype

3. **Import `game.css` in `app.css`**:
   - Add `@import "./game.css";` after the Tailwind/daisyUI imports
   - Ensure `@source` directives cover the game CSS

4. **Create `lib/agenticrealms/game_data.ex`**:
   - Module with public functions returning mock data as maps/lists
   - `rooms/0` → room data (The Gilded Kraken)
   - `starting_log/0` → initial narrative log entries
   - `player_stats/0` → character stats
   - `inventory/0` → inventory items
   - `quests/0` → quest summaries
   - `quest_details/0` → detailed quest data for modal
   - `presence/0` → room presence entries
   - `suggestions/0` → command suggestion chips
   - `wizard_examples/0` → map of content kind → example data
   - `starter_prompts/0` → map of content kind → starter text
   - `map_nodes/0` → mini-map node positions
   - `map_edges/0` → mini-map connections

5. **Update `root.html.heex`**:
   - Set default `data-theme="phosphor"` on `<html>` element
   - Update theme script to handle phosphor/paper/dusk instead of system/light/dark

### Phase B: LiveView + Routing

**Goal**: Create the main LiveView with mode switching, wired to mock data.

1. **Create `lib/agenticrealms_web/live/game_live.ex`**:
   - `mount/3`: Load all mock data from `GameData` into assigns
   - `handle_event/3` for: `switch_mode`, `submit_command`, `open_modal`, `close_modal`, `toggle_map`, `set_wizard_kind`, `update_wizard_text`, `open_trigger`, `close_trigger`, `set_tweak`, `toggle_tweaks`, `click_suggestion`, `select_quest`
   - Command submission logic: pattern match on input text to produce appropriate mock responses (narrate, system, combat entries)

2. **Create `lib/agenticrealms_web/live/game_live.html.heex`**:
   - Render topbar with mode switch
   - Conditionally render player or wizard view based on `@mode`
   - Render tweaks panel when `@tweaks_open`

3. **Update `router.ex`**:
   - Replace `get "/", PageController, :home` with `live "/", GameLive`

4. **Create a custom game layout in `layouts.ex`**:
   - Define a `game/1` layout function that provides a minimal shell (no default navbar/footer) suitable for the full-viewport game UI
   - Or override the `app/1` layout for the game route

### Phase C: Player View Components

**Goal**: Build all player-facing UI components.

1. **Create `lib/agenticrealms_web/components/game_components.ex`**:
   - Start with `use AgenticRealmsWeb, :html`
   - Define all function components with `attr` declarations

2. **Implement player view components**:
   - `topbar/1` — branding, mode switch pill, user info
   - `player_view/1` — grid layout container with data-layout/data-hud/data-map attributes
   - `log_entry/1` — renders each log entry type (room, narrate, cmd, said, whisper, system, combat) with distinct markup
   - `room_entry/1` — room header, description, exit chips, entity listings
   - `hp_bar/1` — stat bar (HP/MP/XP) with label and percentage fill
   - `hud_card/1` — collapsible card with clickable header and expand icon
   - `stats_panel/1` — sidebar with Character card (who-card, bars), Inventory card, Quest Log card, Present card
   - `mini_map/1` — SVG-based map with nodes, edges, grid, and directional pad
   - `input_bar/1` — command input with map toggle, prompt character, send button, suggestion chips

3. **Implement modal components**:
   - `modal/1` — generic modal shell (backdrop, close button, escape handler via JS)
   - `stats_modal/1` — full character sheet with avatar, bars, ability score grid
   - `inventory_modal/1` — filterable tile grid with equipped markers
   - `quest_modal/1` — two-pane layout with quest nav and detail view
   - `presence_modal/1` — card grid with whisper/inspect actions

4. **Wire escape-to-close** for modals using `phx-window-keydown` on the LiveView or `Phoenix.LiveView.JS` commands.

### Phase D: Wizard View Components

**Goal**: Build all wizard/creator UI components.

1. **Implement wizard view components**:
   - `wizard_view/1` — split-pane layout (left prompt, right preview)
   - `kind_picker/1` — row of kind chip buttons (Room, NPC, Item, Quest, Spell)
   - `wizard_input/1` — textarea with hint, word/token counts, footer actions
   - `data_card/1` — interpreted data card with progressive field reveal based on text length
   - `wizard_field/1` — renders field by kind (prose, tag, tags, num, exits, entities, stats, loot, adjectives, steps, rewards)
   - `ingame_preview/1` — "As player would see it" panel with simulated room rendering

2. **Implement trigger components**:
   - `trigger_section/1` — section header + trigger flow container
   - `trigger_compact_card/1` — compact clickable card (intent token, action count, chevron)
   - `trigger_modal/1` — full detail modal (matching, conditions, note, actions, footer)
   - `conditions_editor/1` — numbered condition rows with subject/operator/value
   - `action_row/1` — numbered action step with kind pill and typed arguments

3. **Handle wizard state**:
   - Kind switching resets starter prompt (unless user edited)
   - Progressive reveal: `visible_fields = min(total_fields, max(2, div(String.length(text), 20)))`
   - Quest kind hides "As player would see it" panel; data card expands

### Phase E: Theme System + Layout Variants

**Goal**: Wire up the tweaks panel and all visual variants.

1. **Implement tweaks panel**:
   - `tweaks_panel/1` — floating panel with theme/density/layout/preview/HUD controls
   - Theme switching: `handle_event("set_tweak")` updates assigns and dispatches JS to set `data-theme` on HTML element
   - Density switching: same pattern with `data-density`

2. **Implement layout variants**:
   - Player grid CSS already handles `data-layout="classic|panels|minimal"` via CSS selectors
   - LiveView passes `@tweaks.player_layout` as data attribute
   - Map visibility controlled by `@map_open` and layout-specific grid areas
   - HUD visibility controlled by `@tweaks.show_hud` via `data-hud` attribute

3. **Colocated JS hook for theme persistence**:
   - `.ThemeSwitch` hook: listens for `set_theme` push_event, sets `data-theme` + localStorage

### Phase F: Streaming Text + Interactive Polish

**Goal**: Add the streaming text animation and final interactive behaviors.

1. **Colocated JS hook `.StreamingText`**:
   - Mounted on a container element in the log
   - Receives full text via `push_event("stream_text", %{text: text})`
   - Reveals 5 characters per 14ms with a blinking cursor span
   - On completion, calls `pushEvent("stream_done", {})` to update server state

2. **Wire command responses**:
   - "read letter" / "open letter" → trigger streaming response
   - Directional commands → system message ("You cannot leave")
   - "attack" / "hit" → combat log entry
   - "inventory" → open inventory modal
   - "quest" → open quest modal
   - Other → generic system message

3. **Auto-scroll log** on new entries using a `.ScrollBottom` colocated hook

### Phase G: Testing

**Goal**: Verify all components render correctly with mocked data.

1. **Create `test/agenticrealms_web/live/game_live_test.exs`**:
   - Test mount renders player view by default
   - Test mode switching to wizard view
   - Test each HUD card modal opens/closes
   - Test command submission adds to log
   - Test map toggle shows/hides map panel
   - Test wizard kind switching
   - Test that all three themes apply without errors

2. **Run `mix precommit`** to verify:
   - No compilation warnings
   - Code formatted
   - All tests pass

## Complexity Tracking

No constitution violations to justify — the design is straightforward:
- 1 LiveView, ~15 function components, 1 data module
- No LiveComponents, no complex routing, no database, no external services

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Routing | Single LiveView at `/` | Matches prototype's single-page design; instant mode switching |
| Components | Function components only | AGENTS.md directive; no independent state needed |
| CSS strategy | Custom properties + dedicated game.css | Design has 2200 lines of purpose-built CSS; Tailwind utilities insufficient alone |
| Theme system | `data-theme` on HTML element | Matches existing Phoenix pattern; instant switching via CSS |
| Font loading | Self-hosted in priv/static/fonts | AGENTS.md prohibits external CDN links |
| Mock data | Elixir module (`GameData`) | User constraint: "Mock the data in the views rather than in the html heex templates" |
| Streaming text | Colocated JS hook | Server round-trip too slow for 14ms character animation |
| daisyUI | Not used in game views | AGENTS.md directive + game has its own design language |
| Modals | JS-driven close (escape/backdrop) | Standard Phoenix pattern with `phx-window-keydown` |
