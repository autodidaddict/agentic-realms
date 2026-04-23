# Tasks: GUI Design Language

**Input**: Design documents from `specs/001-gui-design-language/`  
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ui-components.md

**Tests**: No comprehensive UI testing for this phase. Visual verification against the original design HTML is sufficient.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Project initialization — fonts, CSS design system, mock data module

- [x] T001 [P] Download and install JetBrains Mono (400, 600, 700), IBM Plex Mono (400, 400i), and Fraunces (400, 500, 600) web fonts into `priv/static/fonts/` as woff2 files
- [x] T002 [P] Create `assets/css/game.css` with `@font-face` declarations for all three font families pointing to `/fonts/` paths, and the complete CSS custom property system: `:root` variables for the phosphor theme (--bg, --bg-elev, --bg-sunken, --bg-inset, --line, --line-soft, --ink, --ink-dim, --ink-faint, --ink-ghost, --player, --player-dim, --player-bg, --wizard, --wizard-dim, --wizard-bg, --danger, --mana, --xp, --mono, --prose, --serif, --pad, --gap, --radius, --radius-lg, --fs-xs through --fs-xl), `[data-theme="paper"]` overrides, `[data-theme="dusk"]` overrides, and `[data-density="compact"]` overrides. Copy all color values from the design prototype at `/tmp/agentic-realms-design/agentic-realms/project/styles.css`
- [x] T003 [P] Add app shell CSS to `assets/css/game.css`: `.app` grid layout (topbar + content), `.topbar` flex layout, `.brand` styling, `.mode-switch` button group with `.active` states and `[data-mode]` coloring, `.top-center`, `.top-right` with `.kbd` badges. Copy from the design's styles.css "App shell" section
- [x] T004 [P] Create `lib/agenticrealms/game_data.ex` with all mock data functions: `rooms/0` (The Gilded Kraken tavern with exits and entities), `starting_log/0` (7 log entries: room, narrate, system, cmd, narrate, said, whisper), `player_stats/0` (Veyr of Ashfall, Cleric lvl 7), `inventory/0` (7 items with equipped flags), `quests/0` (2 quest summaries), `quest_details/0` (2 detailed quests with steps and rewards), `presence/0` (4 entities), `suggestions/0` (6 command chips), `map_nodes/0` (5 nodes with positions), `map_edges/0` (4 edges), `wizard_examples/0` (map of :room, :npc, :item, :quest, :spell to WizardExample maps), `starter_prompts/0` (map of kind to prompt text). Translate all data structures from `/tmp/agentic-realms-design/agentic-realms/project/src/data.jsx`
- [x] T005 Add `@import "./game.css";` to `assets/css/app.css` after the existing daisyUI plugin imports (after line 18)
- [x] T006 Update `lib/agenticrealms_web/components/layouts/root.html.heex`: set `data-theme="phosphor"` on the `<html>` element, replace the existing theme script to handle phosphor/paper/dusk themes instead of system/light/dark

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: LiveView, routing, game layout, and component module — MUST complete before any user story

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T007 Create `lib/agenticrealms_web/components/game_components.ex` with `use AgenticRealmsWeb, :html` and initial `topbar/1` function component (attrs: mode, stats) rendering the app topbar with brand mark "A", "Agentic Realms", separator, "Blackvane server", mode switch pill (Player/Wizard buttons with dot indicators and active state), and top-right area with player name and keyboard shortcut badge
- [x] T008 Add `import AgenticRealmsWeb.GameComponents` to the `html_helpers/0` function in `lib/agenticrealms_web.ex` so game components are available in all templates
- [x] T009 Create a `game/1` layout function in `lib/agenticrealms_web/components/layouts.ex` that renders a minimal full-viewport shell: just `{render_slot(@inner_block)}` wrapped in a div with `<.flash_group flash={@flash} />`, no default navbar/footer. Accept `flash` and `current_scope` attrs
- [x] T010 Create `lib/agenticrealms_web/live/game_live.ex` with `use AgenticRealmsWeb, :live_view`. In `mount/3`: load all mock data from `AgenticRealms.GameData` into assigns (mode: :player, modal: nil, map_open: false, log: starting_log, input: "", streaming: false, stats, inventory, quests, quest_details, presence, suggestions, wizard_kind: :item, wizard_text: starter_prompt for :item, wizard_user_edited: false, open_trigger: nil, tweaks: default map, tweaks_open: false). Add `handle_event/3` for "switch_mode" (updates mode assign)
- [x] T011 Create `lib/agenticrealms_web/live/game_live.html.heex` that wraps content in `<Layouts.game flash={@flash}>`, renders `<.topbar mode={@mode} stats={@stats} />`, and a placeholder div for the current mode ("Player view coming soon" or "Wizard view coming soon" based on `@mode`)
- [x] T012 Update `lib/agenticrealms_web/router.ex`: replace `get "/", PageController, :home` with `live "/", GameLive` inside the browser scope. The scope already has `AgenticRealmsWeb` alias so use just `GameLive`

**Checkpoint**: App compiles, visiting `http://localhost:4000` shows the topbar with mode switching between placeholder views

---

## Phase 3: User Story 1 — Player Views Game World (Priority: P1) MVP

**Goal**: Render the complete player view with narrative text log, stats sidebar, and text input

**Independent Test**: Load the player view and verify: topbar renders, narrative log shows all 7 mock entries with correct styling per type, stats sidebar shows Character/Inventory/Quest Log/Present HUD cards, input bar with suggestion chips is visible

### Implementation for User Story 1

- [x] T013 [P] [US1] Add player view CSS to `assets/css/game.css`: `.player` grid layouts for all `[data-layout]` variants and `[data-map]` states, `.p-log` with scrollbar styling, all `.log-entry` type styles (`.room`, `.narrate` with `::first-letter` drop-cap, `.cmd` with `::before` prompt, `.said` with left border, `.whisper` in serif italic, `.system` with dot prefix, `.combat` with bar), `.room-head`, `.room-body`, `.exits`, `.exit-chip` with hover states, `.entities`, `.entity` with type variants (.item, .npc, .player-other), `.cursor` blink animation. Copy from design styles.css "Player view", "Log" sections
- [x] T014 [P] [US1] Add stats panel CSS to `assets/css/game.css`: `.p-stats` layout (column for classic/panels, row for minimal), `.who-card`, `.sigil`, `.who-name`, `.who-class`, `.stat-label`, `.bar` with `.hp`/`.mp`/`.xp` fill colors, `.hud-card`, `.hud-card-head` with hover, `.hud-card-body`, `.inv-list`, `.quest-item`, `.presence-row`, `.presence-dot`. Copy from design styles.css "Stats panel", "Boxed HUD cards" sections
- [x] T015 [P] [US1] Add input bar CSS to `assets/css/game.css`: `.p-input`, `.p-input-line`, `.p-input-row` with focus-within glow, `.p-input-prompt`, input styling, `.send` button, `.suggest-row`, `.suggest-chip` with hover. Copy from design styles.css "Input bar" section
- [x] T016 [US1] Add `log_entry/1` function component to `game_components.ex` (attr: entry map). Pattern match on `entry.kind` to render the correct markup: `:room` → room-head + room-body + exits as exit-chip buttons + entities; `:narrate` → serif text with drop-cap class; `:cmd` → command with prompt prefix; `:said` → quote with speaker name; `:whisper` → italic serif with blue border; `:system` → monospace with dot; `:combat` → damage bar with numbers
- [x] T017 [US1] Add `hp_bar/1` function component to `game_components.ex` (attrs: label, cur, max, kind). Render stat-label with name and "cur / max" value, plus a `.bar` div with inner `<i>` scaled to percentage
- [x] T018 [US1] Add `hud_card/1` function component to `game_components.ex` (attrs: title, count; slot: inner_block). Render a `.hud-card` with a clickable `.hud-card-head` (title, count, expand SVG icon) that emits `phx-click` to open the modal, and `.hud-card-body` containing the slot
- [x] T019 [US1] Add `stats_panel/1` function component to `game_components.ex` (attrs: stats, inventory, quests, presence, layout). Render the Character hud-card (sigil, name, class, HP/MP/XP bars), and when layout is not "minimal": Inventory hud-card (item list with equipped markers), Quest Log hud-card (quest items), Present hud-card (presence rows with status dots)
- [x] T020 [US1] Add `player_view/1` function component to `game_components.ex` (attrs: log, stats, inventory, quests, presence, suggestions, input, streaming, map_open, tweaks). Render the `.player` div with `data-layout`, `data-hud`, `data-map` attributes. Include: `.p-log` main area iterating log entries with `log_entry/1`, `stats_panel/1` sidebar (when show_hud), and `.p-input` footer with input row (prompt character, text input with `phx-keydown` for Enter, send button) and suggestion chips row
- [x] T021 [US1] Add `handle_event` clauses to `game_live.ex` for: "submit_command" (pattern match input text — "read/open/letter" → set streaming=true; directional → append system entry; "attack/hit" → append combat entry; "inv/inventory" → open modal; "quest" → open modal; other → append generic system entry; always append cmd entry and clear input), "click_suggestion" (same as submit_command with chip text), "update_input" (update input assign)
- [x] T022 [US1] Update `game_live.html.heex` to render `<.player_view>` when `@mode == :player`, passing all player-related assigns

**Checkpoint**: Player view renders with full narrative log, styled entries, stats sidebar with HUD cards, and working command input with suggestion chips

---

## Phase 4: User Story 2 — Player Interacts with HUD Cards (Priority: P1)

**Goal**: Each HUD card header click opens a detailed modal overlay

**Independent Test**: Click each HUD card header → verify correct modal opens with complete mock data. Press Escape or click backdrop → modal closes.

### Implementation for User Story 2

- [x] T023 [P] [US2] Add modal CSS to `assets/css/game.css`: `.modal-backdrop` (fixed overlay with blur), `.modal` (centered card with shadow and slide animation), `.modal-head`, `.modal-title` with `.glyph`, `.modal-close` button, `.modal-body`, `.modal-foot-hint` with `.kbd`. Add stats modal styles: `.stats-grid`, `.stat-row`, `.big-bar-block`. Add inventory modal styles: `.inv-grid`, `.inv-tile` with `.equipped`, `.inv-filter`. Add quest modal styles: `.quest-detail` two-pane grid, `.quest-nav`, `.quest-body`, `.quest-steps`, `.quest-step` with `.done` state, `.reward-row`, `.reward-row .tag`. Add presence modal styles: `.presence-grid`, `.presence-card` with `.other`/`.npc` variants. Copy from design styles.css "Modal", "Stats modal", "Inventory modal", "Quest modal", "Presence modal" sections
- [x] T024 [US2] Add `modal/1` function component to `game_components.ex` (attrs: title, glyph, on_close; slot: inner_block, foot_hint). Render `.modal-backdrop` with `phx-click` to close (using JS or event), `.modal` with head (title, glyph, close button), body (slot), and optional foot hint. Add `phx-window-keydown` with `phx-key="Escape"` to close
- [x] T025 [US2] Add `stats_modal/1` function component to `game_components.ex` (attrs: stats). Render character sheet: sigil (80x80), name, class, description text, HP/MP/XP bars with regeneration hints, and ability scores grid (Str/Dex/Wis/Cha/Con/Int with values and modifiers)
- [x] T026 [US2] Add `inventory_modal/1` function component to `game_components.ex` (attrs: inventory). Render filter input, capacity label, and tile grid of items with name, carried/worn status, quantity badge, and equipped marker
- [x] T027 [US2] Add `quest_modal/1` function component to `game_components.ex` (attrs: quest_details, selected_quest). Render two-pane layout: quest nav (button list with titles and step progress), quest body (title, giver, synopsis, description, step checklist with checkmarks, reward tags). Handle quest selection via `phx-click` event
- [x] T028 [US2] Add `presence_modal/1` function component to `game_components.ex` (attrs: presence). Render card grid with avatar initial, name, role/status, and whisper/inspect action buttons for each entity
- [x] T029 [US2] Add `handle_event` clauses to `game_live.ex` for: "open_modal" (set modal assign to the modal type atom), "close_modal" (set modal to nil), "select_quest" (update selected_quest index). Add `selected_quest: 0` to mount assigns
- [x] T030 [US2] Update `player_view/1` in `game_components.ex` and `game_live.html.heex` to render the appropriate modal component when `@modal` is set (`:stats` → stats_modal, `:inv` → inventory_modal, `:quests` → quest_modal, `:presence` → presence_modal). Pass the `phx-click` events from hud_card headers to "open_modal" with the modal type

**Checkpoint**: All four HUD card modals open/close correctly with complete mock data

---

## Phase 5: User Story 4 — Wizard Edits Room Content (Priority: P1)

**Goal**: Wizard mode shows split-pane editor with prompt, kind picker, interpreted data card with progressive reveal, and in-game preview panel

**Independent Test**: Switch to Wizard mode → verify kind picker, prompt textarea with starter text, interpreted data card showing room fields, and "As player would see it" preview renders correctly

### Implementation for User Story 4

- [x] T031 [P] [US4] Add wizard view CSS to `assets/css/game.css`: `.wizard` two-column grid, `.w-left` (flex column with border), `.w-head`, `.w-input-wrap`, `.w-input` textarea styling with focus glow, `.w-prompt-label` with `.hint`, `.w-kind-picker`, `.kind-chip` with `.active` state, `.w-footer` with `.meta`, `.pulse` animation, `.btn-ghost`, `.btn-primary`. Copy from design styles.css "Wizard view" section
- [x] T032 [P] [US4] Add wizard right-side CSS to `assets/css/game.css`: `.w-right` grid, `.w-pane` with border, `.w-pane-head` with `.lbl`, `.w-pane-body`, `.data-card`, `.dc-header` with `.icon`/`.ids`/`.dc-title`/`.dc-slug`/`.dc-status`, `.dc-field` with `.k`/`.v` and progressive `fadeIn` animation, `.dc-field .v.prose`, `.dc-field .v.tag-list`, `.dc-field .v .tag` with `.key`/`.num` variants, `.exit-pair`, `.ingame-preview` with `::before` label, `.empty-preview`. Copy from design styles.css "Wizard right side", "Card preview", "In-game preview" sections
- [x] T033 [US4] Add `kind_picker/1` function component to `game_components.ex` (attr: value). Render `.w-kind-picker` with kind-chip buttons for Room, NPC, Item, Quest, Spell. Active chip gets `.active` class. Each emits `phx-click="set_wizard_kind"` with `phx-value-kind`
- [x] T034 [US4] Add `wizard_field/1` function component to `game_components.ex` (attr: field map). Pattern match on `field.kind` to render: "prose" → plain text span; "tag" → split on `·` or `,` into tag chips; "tags" → iterate items as tag chips; "num" → tag with num class; "exits" → exit-pair rows with direction, arrow, destination; "entities" → tag chips with name and type. Add `fadeIn` animation delay via inline style
- [x] T035 [US4] Add `data_card/1` function component to `game_components.ex` (attrs: example map, visible_field_count). Render `.data-card` with `.dc-header` (icon, title, slug, "draft · unsaved" status), then iterate `example.fields` up to `visible_field_count`, rendering each with `wizard_field/1`
- [x] T036 [US4] Add `wizard_view/1` function component to `game_components.ex` (attrs: kind, text, tweaks, open_trigger, wizard_examples, visible_field_count). Render `.wizard` split layout: left pane with head ("Wizard mode · creator", "Describing a {kind}"), kind_picker, hint text, textarea with `phx-change`, word/token counts, footer (pulse indicator, Discard/Save as draft/Commit to world buttons); right pane with "Interpreted Data" pane (data_card or empty state), and "As player would see it" pane (hidden for quest kind, shows ingame HTML preview otherwise)
- [x] T037 [US4] Add `handle_event` clauses to `game_live.ex` for: "set_wizard_kind" (update wizard_kind, reset wizard_text to starter prompt if not user-edited), "update_wizard_text" (update wizard_text, set wizard_user_edited to true)
- [x] T038 [US4] Update `game_live.html.heex` to render `<.wizard_view>` when `@mode == :wizard`, passing wizard assigns. Compute `visible_field_count` from `String.length(@wizard_text)` using formula: `min(total_fields, max(2, div(text_length, 20)))`

**Checkpoint**: Wizard mode renders with kind picker, room data card with progressive reveal, and in-game preview

---

## Phase 6: User Story 3 — Player Uses Map and Input Controls (Priority: P2)

**Goal**: Map toggle button shows/hides mini-map panel, suggestion chips work

**Independent Test**: Click map toggle → map panel appears with grid, nodes, edges, directional pad. Click again → map hides.

### Implementation for User Story 3

- [x] T039 [P] [US3] Add map panel CSS to `assets/css/game.css`: `.p-side-left` panel styling, `.map` with aspect-ratio, `.map-grid` background pattern, `.map-node` with `.current` (glow), `.visited`, `.map-edge`, `.dir-pad` grid with button styling. Add `.map-toggle` button styling with `.open` state. Copy from design styles.css "Left side panel", "Map toggle button" sections
- [x] T040 [US3] Add `mini_map/1` function component to `game_components.ex`. Render `.map` container with grid overlay div, map edges (absolutely positioned divs with calculated width/rotation from node positions), map nodes (absolutely positioned divs with state classes), and a directional pad grid (N/S/E/W/center buttons)
- [x] T041 [US3] Add `handle_event` clause to `game_live.ex` for "toggle_map" (toggle map_open boolean assign)
- [x] T042 [US3] Update `player_view/1` in `game_components.ex` to include: map toggle button (SVG map icon, no label) inside `.p-input-line` to the left of `.p-input-row`; and conditionally render `.p-side-left` panel with `mini_map/1` when `map_open` is true

**Checkpoint**: Map toggle works, mini-map panel renders with nodes and directional pad

---

## Phase 7: User Story 5 — Wizard Edits Item Content (Priority: P2)

**Goal**: Item kind shows name, pickable, short/long description, adjectives chips

**Independent Test**: Select Item kind → data card shows astrolabe fields with adjective chips

### Implementation for User Story 5

- [x] T043 [P] [US5] Add adjectives CSS to `assets/css/game.css`: `.dc-adj`, `.dc-adj-chips`, `.dc-adj-chip` (amber removable pills with `×` button), `.dc-adj-add` (dashed add button), `.dc-adj-note`. Copy from design styles.css adjective chip section
- [x] T044 [US5] Extend `wizard_field/1` in `game_components.ex` to handle "adjectives" kind: render `.dc-adj` with `.dc-adj-chips` containing `.dc-adj-chip` for each item (text + `×` span), an `.dc-adj-add` "+ add" button, and `.dc-adj-note` with the note text

**Checkpoint**: Item editor renders all fields including adjective chips

---

## Phase 8: User Story 6 — Wizard Edits NPC Content (Priority: P2)

**Goal**: NPC kind shows stats grids, loot table, adjectives

**Independent Test**: Select NPC kind → data card shows Malveth with stats grid, loot table, adjectives

### Implementation for User Story 6

- [x] T045 [P] [US6] Add stats grid and loot CSS to `assets/css/game.css`: `.dc-stats-grid` (2-column grid), `.dc-stat` (3-column with k/v/sub), `.dc-loot` grid, `.dc-loot-row` (name + chance percentage with amber left border). Copy from design styles.css stats/loot sections
- [x] T046 [US6] Extend `wizard_field/1` in `game_components.ex` to handle "stats" kind: render `.dc-stats-grid` with `.dc-stat` cells (key label, value, optional modifier sub-text). Handle "loot" kind: render `.dc-loot` with `.dc-loot-row` for each item (name + percentage chance)

**Checkpoint**: NPC editor renders stats, loot, and all NPC-specific fields

---

## Phase 9: User Story 7 — Wizard Edits Quest Content (Priority: P2)

**Goal**: Quest kind shows steps with IDs, typed rewards, no preview panel

**Independent Test**: Select Quest kind → data card fills full height, shows steps and rewards, no "As player would see it" panel

### Implementation for User Story 7

- [x] T047 [P] [US7] Add steps and rewards CSS to `assets/css/game.css`: `.dc-steps`, `.dc-step-row` (numbered cards with id and description), `.dc-rewards`, `.dc-reward-row` (kind label + value with optional label). Copy from design styles.css steps/rewards sections
- [x] T048 [US7] Extend `wizard_field/1` in `game_components.ex` to handle "steps" kind: render `.dc-steps` with numbered `.dc-step-row` cards (step number, ID in faint text, description in prose). Handle "rewards" kind: render `.dc-rewards` with `.dc-reward-row` for each reward (kind label, value, optional human label)

**Checkpoint**: Quest editor renders steps and rewards, preview panel hidden, data card fills space

---

## Phase 10: User Story 8 — Wizard Manages Triggers (Priority: P2)

**Goal**: Triggers render as compact cards, clicking opens detail modal with conditions and actions

**Independent Test**: View room/item/NPC with triggers → compact cards visible. Click card → detail modal opens with intent, conditions, actions.

### Implementation for User Story 8

- [x] T049 [P] [US8] Add trigger CSS to `assets/css/game.css`: `.trigger-section`, `.trigger-section-head`, `.trigger-flow`, `.trigger-card` with `::before` amber left accent, `.trigger-card-compact` grid (intent token, action count pill, chevron), `.token` with `.intent`/`.target` variants, `.chain-arrow`, `.add-trigger-btn`. Add trigger modal CSS: `.trg-modal-head`, `.trg-modal-section`, `.trg-field` with label/input/select styling, `.trg-add-action`, action row styles (`.action-row` with step number, kind pill, action body spans). Add conditions CSS: `.cond-list`, `.cond-row` (5-column grid), `.cond-num`, `.cond-subject`, `.cond-op`, `.cond-value`, `.cond-remove`, `.cond-hint`, `.cond-empty`. Copy from design styles.css "Trigger flow cards", "Conditions editor" sections
- [x] T050 [US8] Add `trigger_compact_card/1` function component to `game_components.ex` (attr: trigger map). Render `.trigger-card` with `.trigger-card-compact` containing intent token (`.token.intent`), action count pill, and chevron. Emit `phx-click="open_trigger"` with trigger ID
- [x] T051 [US8] Add `conditions_editor/1` function component to `game_components.ex` (attr: conditions list). Render `.cond-list`: if empty show `.cond-empty` placeholder; otherwise render numbered `.cond-row` for each condition (number badge, subject, operator label mapped from op code, quoted value, remove button). Add "+ add condition" button and "all must be true" hint
- [x] T052 [US8] Add `action_row/1` function component to `game_components.ex` (attrs: index, action map). Render `.action-row` with step number circle, kind pill (mapped from action.kind to label), and action body with type-specific content: emit_text → scope + quoted text; modify_prop → target + prop = value; spawn_entity → target + attrs; set_disposition → target + value; grant_item → target + item; require_input → target + prompt
- [x] T053 [US8] Add `trigger_modal/1` function component to `game_components.ex` (attr: trigger map). Render the full detail modal: header with trigger label and intent token; Matching section with Intent dropdown (options: Friendly Touch, Look, Use, Take, Attack, Speak, Whisper, Move); Conditions section with `conditions_editor/1`; Note section with italic text; Actions section with numbered `action_row/1` entries and "+ add action" button; footer with fire-count stat and Duplicate/Delete/Save buttons
- [x] T054 [US8] Add `trigger_section/1` function component to `game_components.ex` (attr: triggers list). Render `.trigger-section` with "TRIGGERS" header and `.trigger-flow` containing `trigger_compact_card/1` for each trigger plus an "+ add trigger" button
- [x] T055 [US8] Update `data_card/1` in `game_components.ex` to render `trigger_section/1` below the fields when `example.triggers` is present and non-empty
- [x] T056 [US8] Add `handle_event` clauses to `game_live.ex` for: "open_trigger" (find trigger by ID from current wizard example's triggers, set open_trigger assign), "close_trigger" (set open_trigger to nil). Update `game_live.html.heex` to render `trigger_modal/1` when `@open_trigger` is set

**Checkpoint**: Trigger compact cards render on room/item/NPC views. Click opens detail modal with all sections.

---

## Phase 11: User Story 9 — Player View Layout Variants (Priority: P3)

**Goal**: Three layout variants (classic/panels/minimal) and tweaks panel for theme/density switching

**Independent Test**: Open tweaks panel → switch between themes, layouts, density. Verify all combinations render without visual breakage.

### Implementation for User Story 9

- [x] T057 [P] [US9] Add tweaks panel CSS to `assets/css/game.css`: `.tweaks` fixed panel with shadow, `.tweaks h3` with "tweaks" badge, `.tweak-field`, `.seg` segmented control with `.active` state, `.toggle` switch with checkbox styling. Copy from design styles.css "Tweaks panel" section
- [x] T058 [US9] Add `tweaks_panel/1` function component to `game_components.ex` (attr: tweaks map). Render `.tweaks` panel with: Theme segmented control (phosphor/paper/dusk), Density segmented control (comfortable/compact), Player layout segmented control (classic/panels/minimal), Wizard preview default segmented control (card/ingame), Show player HUD toggle switch. Each control emits `phx-click="set_tweak"` with key and value
- [x] T059 [US9] Add `handle_event` clauses to `game_live.ex` for: "set_tweak" (update tweaks map assign with the key/value pair), "toggle_tweaks" (toggle tweaks_open boolean). For theme changes, also use `push_event` to dispatch a client-side theme set
- [x] T060 [US9] Add colocated JS hook `.ThemeSwitch` in `game_live.html.heex` — mount it on a persistent element, listen for `set_theme` push_event, set `data-theme` and `data-density` attributes on `document.documentElement` and persist to localStorage
- [x] T061 [US9] Update `game_live.html.heex` to include a tweaks toggle button (e.g., gear icon) in the topbar or as a floating button, render `tweaks_panel/1` when `@tweaks_open` is true, and wire the `.ThemeSwitch` hook to the root game container

**Checkpoint**: All three themes and layouts apply correctly. Tweaks panel opens/closes and persists preferences.

---

## Phase 12: Polish & Cross-Cutting Concerns

**Purpose**: Streaming text animation, auto-scroll, and visual verification

- [x] T062 [P] Add colocated JS hook `.StreamingText` in `game_live.html.heex` — reveals text character by character (5 chars per 14ms) with a blinking cursor span. Receives full text via `handleEvent("stream_text")`, calls `pushEvent("stream_done")` when complete
- [x] T063 [P] Add colocated JS hook `.ScrollBottom` in `game_live.html.heex` — auto-scrolls the `.p-log` container to the bottom whenever its content updates (mounted + updated callbacks)
- [x] T064 Wire streaming text in `game_live.ex`: when "submit_command" detects a read/letter command, push "stream_text" event with the full response text and set streaming=true. Add "stream_done" handler to set streaming=false and append the narrate entry to the log. Update `player_view/1` to show a streaming container with `.StreamingText` hook when `@streaming` is true
- [x] T065 Wire `.ScrollBottom` hook on the `.p-log` element in `player_view/1`
- [x] T066 Add remaining keyframe animations to `assets/css/game.css` if not already present: `@keyframes fadeIn`, `@keyframes blink`, `@keyframes flash`, `@keyframes pulse`, `@keyframes slideModal`, `@keyframes fadeModal`. Verify all animations referenced in CSS classes are defined
- [x] T067 Run `mix compile --warnings-as-errors` and `mix format` to verify clean compilation
- [x] T068 Visual verification: start dev server with `mix phx.server`, open `http://localhost:4000` in browser, compare player view and wizard view side-by-side with the original design HTML at `/tmp/agentic-realms-design/agentic-realms/project/Agentic Realms.html`. Verify layout, typography, colors, and component rendering match closely

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on T005 (CSS import) from Setup — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 completion
- **US2 (Phase 4)**: Depends on US1 (needs player view with HUD cards to click)
- **US4 (Phase 5)**: Depends on Phase 2 completion (independent of US1/US2)
- **US3 (Phase 6)**: Depends on US1 (extends player view with map)
- **US5 (Phase 7)**: Depends on US4 (extends wizard field renderer)
- **US6 (Phase 8)**: Depends on US4 (extends wizard field renderer)
- **US7 (Phase 9)**: Depends on US4 (extends wizard field renderer)
- **US8 (Phase 10)**: Depends on US4 (extends wizard data card)
- **US9 (Phase 11)**: Depends on US1 and US4 (tweaks affect both views)
- **Polish (Phase 12)**: Depends on US1 (streaming text in player view)

### User Story Dependencies

- **US1 (P1)**: After Phase 2 — no story dependencies
- **US4 (P1)**: After Phase 2 — no story dependencies, can run in parallel with US1
- **US2 (P1)**: After US1
- **US3 (P2)**: After US1
- **US5, US6, US7 (P2)**: After US4, can run in parallel with each other
- **US8 (P2)**: After US4
- **US9 (P3)**: After US1 and US4

### Parallel Opportunities

- T001, T002, T003, T004 (Phase 1 setup tasks) — all different files
- T013, T014, T015 (US1 CSS tasks) — all append to same file but different sections
- US1 and US4 — completely independent, can run in parallel after Phase 2
- US5, US6, US7 — independent wizard field extensions, can run in parallel
- T062, T063 (Polish JS hooks) — independent colocated hooks

---

## Parallel Example: Phase 1 Setup

```bash
# All four setup tasks can run in parallel:
Task: "T001 - Download fonts to priv/static/fonts/"
Task: "T002 - Create game.css with design system variables"
Task: "T003 - Add app shell CSS"
Task: "T004 - Create game_data.ex with mock data"
```

## Parallel Example: User Stories 1 + 4

```bash
# After Phase 2, both P1 stories can start simultaneously:
# Stream 1: Player View (US1)
Task: "T013-T015 - Player CSS (parallel)"
Task: "T016-T022 - Player components and events"

# Stream 2: Wizard View (US4)
Task: "T031-T032 - Wizard CSS (parallel)"
Task: "T033-T038 - Wizard components and events"
```

---

## Implementation Strategy

### MVP First (User Stories 1 + 4)

1. Complete Phase 1: Setup (fonts, CSS, data)
2. Complete Phase 2: Foundational (LiveView, routing)
3. Complete Phase 3: US1 — Player View
4. Complete Phase 5: US4 — Wizard View
5. **STOP and VALIDATE**: Both core views render correctly
6. Compare visually with design prototype

### Incremental Delivery

1. Setup + Foundational → App loads with topbar
2. US1 → Player view with log and sidebar
3. US2 → HUD card modals work
4. US4 → Wizard view with data card
5. US3 → Map toggle works
6. US5+US6+US7 → All wizard content kinds render
7. US8 → Trigger editor works
8. US9 → Themes and layouts switchable
9. Polish → Streaming text, final verification

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- No automated UI tests in this phase — visual verification only
- The design reference CSS at `/tmp/agentic-realms-design/agentic-realms/project/styles.css` should be consulted for exact CSS values
- Commit after each phase checkpoint
- Stop at any checkpoint to verify visual fidelity against the design
