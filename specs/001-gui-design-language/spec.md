# Feature Specification: GUI Design Language

**Feature Branch**: `001-gui-design-language`  
**Created**: 2026-04-22  
**Status**: Draft  
**Input**: User description: "GUI design language for Agentic Realms — UI foundations for player and wizard views as Phoenix LiveView controls with mocked data"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Player Views Game World (Priority: P1)

A player navigates to the application and sees a dark, terminal-revival themed interface. The main area displays a narrative text log showing room descriptions, dialogue, whispers, system messages, and combat events. A sidebar shows collapsible HUD cards for Character stats, Inventory, Quest Log, and Present entities. Below the log is a text input area with a send button and suggestion chips for common actions.

**Why this priority**: The player view is the core experience of the game. Without it, users cannot interact with the world at all. This is the foundational screen that establishes the entire design language.

**Independent Test**: Can be fully tested by loading the player view, verifying the layout renders correctly with mocked data (rooms, log entries, stats, inventory, quests, presence), and confirming the visual design matches the terminal-revival aesthetic.

**Acceptance Scenarios**:

1. **Given** a player loads the application, **When** the player view renders, **Then** they see a topbar with "Agentic Realms" branding, a Player/Wizard mode switch, and user info; a narrative log area with room description, exits as clickable chips, and entity listings; a stats sidebar with Character, Inventory, Quest Log, and Present HUD cards; and a text input bar with suggestion chips.
2. **Given** the player view is displayed, **When** the player views the narrative log, **Then** room entries show the room name, coordinate, description text, exit chips (directional), and entities listed with type-based styling (NPCs, items, other players each styled distinctly).
3. **Given** the player view is displayed, **When** the player views log entries, **Then** different entry types render with distinct visual treatments: narrate entries use serif font with drop-cap first letter, command entries show a green prompt character, dialogue entries have a colored left border, whisper entries use italic serif styling with a blue accent, system messages use monospace with a dot prefix, and combat entries show a red-accented bar with damage numbers.

---

### User Story 2 - Player Interacts with HUD Cards (Priority: P1)

A player clicks on any HUD card header (Character, Inventory, Quest Log, Present) to open a detailed modal overlay providing richer interaction with that data.

**Why this priority**: The expandable HUD cards are the primary way players access detailed game state. They are integral to the player experience and tightly coupled with the player view.

**Independent Test**: Can be tested by clicking each HUD card header and verifying the correct modal opens with the expected content layout and mock data.

**Acceptance Scenarios**:

1. **Given** the player view is displayed, **When** the player clicks the Character card header, **Then** a modal opens showing a full character sheet with avatar sigil, name, class, HP/MP/XP bars, a character description, and a grid of ability scores (Strength, Dexterity, Wisdom, Charisma, Constitution, Intellect).
2. **Given** the player view is displayed, **When** the player clicks the Inventory card header, **Then** a modal opens showing a filterable tile grid of items with equipped markers, item names, carried/worn status, and quantity badges.
3. **Given** the player view is displayed, **When** the player clicks the Quest Log card header, **Then** a modal opens showing a two-pane layout with quest list on the left (with step progress) and detailed quest view on the right (synopsis, description, step checklist with completion states, and reward tags).
4. **Given** the player view is displayed, **When** the player clicks the Present card header, **Then** a modal opens showing a card grid of entities in the room with avatar initials, name, role/status, and whisper/inspect action buttons.
5. **Given** any modal is open, **When** the player presses Escape or clicks the backdrop, **Then** the modal closes.

---

### User Story 3 - Player Uses Map and Input Controls (Priority: P2)

A player can toggle a mini-map panel via a map icon button adjacent to the input box, type commands into the text input, and click suggestion chips to submit pre-defined actions.

**Why this priority**: Map navigation and command input are secondary to the core display but essential for the interactive feel of the prototype.

**Independent Test**: Can be tested by clicking the map toggle to show/hide the map panel, typing text in the input and pressing Enter, and clicking suggestion chips.

**Acceptance Scenarios**:

1. **Given** the player view is displayed, **When** the player clicks the map toggle button (to the left of the input box border), **Then** a side panel slides in showing a mini-map with grid overlay, positioned nodes (current highlighted with glow, visited dimmed, unvisited outlined), connecting edges, and a directional pad (N/S/E/W).
2. **Given** the player view with map visible, **When** the player clicks the map toggle again, **Then** the map panel hides.
3. **Given** the player view is displayed, **When** the player types a command and presses Enter or clicks Send, **Then** the command appears in the log as a command entry, and a mocked response is appended (e.g., typing "read letter" triggers a streaming narration response).
4. **Given** the player view is displayed, **When** the player clicks a suggestion chip, **Then** the chip's text is submitted as a command.

---

### User Story 4 - Wizard Edits Room Content (Priority: P1)

A wizard switches to Wizard mode and sees a split-pane editor. The left pane has a natural language prompt textarea with a kind picker (Room, NPC, Item, Quest, Spell). The right pane shows an "Interpreted Data" card that reveals fields progressively as text is entered, and an "As player would see it" preview panel below.

**Why this priority**: The wizard view is one of the two core flows. Room editing establishes the foundational wizard interaction pattern used by all content types.

**Independent Test**: Can be tested by switching to Wizard mode, selecting "Room" kind, and verifying the interpreted data card shows room-specific fields (biome tags, light, exits, entities) and the preview panel shows an in-game room rendering.

**Acceptance Scenarios**:

1. **Given** the user clicks the "Wizard" mode switch, **When** the wizard view loads, **Then** the left pane shows a kind picker (Room, NPC, Item, Quest, Spell), an italic hint explaining the prompt purpose, a textarea pre-filled with a starter prompt, word/token counts, and a footer with Discard/Save as draft/Commit to world buttons.
2. **Given** the wizard is editing a room, **When** the textarea has sufficient content, **Then** the Interpreted Data card shows: a header with room icon, title, slug path, and draft status; biome as individual tag chips; light level as a tag; exits with directional arrows; and entities with type labels.
3. **Given** the wizard is editing a room, **When** triggers exist on the room, **Then** a "Triggers" section header appears below the entity data, followed by compact trigger cards showing intent and action count. Clicking a trigger card opens a trigger detail modal.
4. **Given** the wizard is editing a room, **When** the "As player would see it" panel is visible, **Then** it shows a simulated in-game rendering of the room with room header, description, exit chips, entity listings, and sample log entries.

---

### User Story 5 - Wizard Edits Item Content (Priority: P2)

A wizard selects "Item" kind and edits an item (defaulting to the Brass Astrolabe). The interpreted data card shows item-specific fields and any attached triggers.

**Why this priority**: Items are a core content type that demonstrates the wizard's ability to define game objects with specific attributes.

**Independent Test**: Can be tested by selecting "Item" kind and verifying fields render correctly with mock data.

**Acceptance Scenarios**:

1. **Given** the wizard selects the "Item" kind, **When** the interpreted data card renders, **Then** it shows: name ("astrolabe"), pickable flag ("false - fixed to reading table"), short description ("a brass astrolabe"), long description (full examine text), and adjectives as removable amber chips with an "+ add" button and "used for target disambiguation" note.
2. **Given** the wizard is viewing an item with triggers, **When** the trigger section renders, **Then** compact trigger cards show the intent (e.g., "Use") and action count, and clicking opens the trigger detail modal.

---

### User Story 6 - Wizard Edits NPC Content (Priority: P2)

A wizard selects "NPC" kind and edits an NPC (defaulting to Malveth). The interpreted data card shows NPC-specific fields including stats grids and loot tables.

**Why this priority**: NPCs demonstrate richer data structures (stats, loot) and establish the pattern for complex entity editing.

**Independent Test**: Can be tested by selecting "NPC" kind and verifying all field types render correctly.

**Acceptance Scenarios**:

1. **Given** the wizard selects the "NPC" kind, **When** the interpreted data card renders, **Then** it shows: name ("Malveth"), short description, long description, adjectives as removable chips, level as a standalone value, HP/MP as a 2-cell stats grid showing max values only, ability scores (Str/Dex/Wis/Cha/Con/Int) as a 6-cell stats grid with modifiers, and loot as a list of items with percentage drop chances.
2. **Given** the wizard is viewing an NPC with triggers, **When** the trigger section renders, **Then** compact trigger cards show the intent (e.g., "Whisper") and clicking opens the trigger detail modal.

---

### User Story 7 - Wizard Edits Quest Content (Priority: P2)

A wizard selects "Quest" kind and edits a quest. The interpreted data card shows quest-specific fields. The "As player would see it" panel is hidden for quests, and the data card expands to fill the full vertical space.

**Why this priority**: Quests demonstrate a content type that intentionally omits the player preview, showing the system's flexibility.

**Independent Test**: Can be tested by selecting "Quest" kind and verifying the layout adjustment and quest-specific fields.

**Acceptance Scenarios**:

1. **Given** the wizard selects the "Quest" kind, **When** the interpreted data card renders, **Then** it shows: giver, goal, steps as numbered cards (each with an ID and player-facing description), and rewards as separate rows (item with ID reference, XP value, faction bonus).
2. **Given** the wizard is viewing a quest, **When** the layout renders, **Then** the "As player would see it" panel is hidden and the interpreted data panel expands to fill all available vertical space.

---

### User Story 8 - Wizard Manages Triggers (Priority: P2)

A wizard interacts with triggers on any content type. Triggers are displayed as compact cards and can be expanded into a detail modal for editing. Each trigger has an intent, conditions, a note, and an ordered list of actions.

**Why this priority**: Triggers are the behavioral rules that make the game world dynamic. The trigger editor is a key differentiator of the wizard experience.

**Independent Test**: Can be tested by clicking a compact trigger card and verifying the detail modal renders all sections correctly.

**Acceptance Scenarios**:

1. **Given** the wizard clicks a compact trigger card, **When** the trigger detail modal opens, **Then** it shows: a header with "Trigger" label and intent token; a Matching section with an Intent dropdown (options: Friendly Touch, Look, Use, Take, Attack, Speak, Whisper, Move); a Conditions section showing numbered condition rows (subject, operator, value) with remove buttons, an "+ add condition" button, and "all must be true" hint; a Note section with italic descriptive text; an Actions section with numbered action steps (kind pill, action body with typed arguments), an "+ add action" button; and a footer with fire-count stat, Duplicate/Delete/Save trigger buttons.
2. **Given** the wizard views trigger conditions, **When** conditions exist, **Then** each condition row shows a numbered badge, a subject (e.g., "room.light"), an operator (e.g., "equals", "has tag", "lacks flag", ">=", "contains"), and a quoted value. No target field is displayed (the owning entity is the implicit target).

---

### User Story 9 - Player View Layout Variants (Priority: P3)

The player view supports three layout variants (classic, panels, minimal) and display tweaks (theme, density, HUD visibility) accessible via a tweaks panel.

**Why this priority**: Layout variants add polish and customization but are not essential for the core experience. They demonstrate the design system's flexibility.

**Independent Test**: Can be tested by toggling layout options in the tweaks panel and verifying the grid layout changes accordingly.

**Acceptance Scenarios**:

1. **Given** the player view is displayed, **When** the layout is "classic", **Then** the log takes the left portion and stats panel the right (280px), with input spanning the full width below.
2. **Given** the player view is displayed, **When** the layout is "panels", **Then** a three-column layout shows map (220px), log (flex), and stats (260px) with input spanning below.
3. **Given** the player view is displayed, **When** the layout is "minimal", **Then** a single-column layout shows a compact stats row at top, centered log (max 720px), and input below. The map and full stats sidebar are hidden.
4. **Given** a tweaks panel is open, **When** the user changes theme, **Then** the color palette updates (phosphor: dark with green/amber accents; paper: light with muted accents; dusk: dark purple with teal/pink accents).

---

### Edge Cases

- What happens when the narrative log has no entries? The log area should render empty without errors.
- What happens when the wizard textarea is under 20 characters? An "empty state" placeholder is shown instead of the data card ("Nothing conjured yet").
- What happens when a content type has no triggers? The triggers section is not rendered.
- What happens when the wizard switches content kinds? The starter prompt updates automatically (unless the user has manually edited the text).
- What happens when all HUD panels are hidden via the tweaks toggle? The stats sidebar disappears and the log expands to fill the width.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST render a Player view with a narrative text log, HUD sidebar with collapsible cards, text input bar, and suggestion chips.
- **FR-002**: System MUST render a Wizard view with a split-pane layout: natural language prompt textarea on the left, interpreted data card and in-game preview on the right.
- **FR-003**: System MUST provide a mode switch in the topbar to toggle between Player and Wizard views.
- **FR-004**: System MUST render distinct visual treatments for each log entry type: room, narrate (with drop-cap), command, dialogue, whisper, system, and combat.
- **FR-005**: System MUST display four HUD cards (Character, Inventory, Quest Log, Present) that open detail modals when their headers are clicked.
- **FR-006**: System MUST provide a map toggle button (map icon only, no label) positioned to the left of the input box border that shows/hides a mini-map side panel.
- **FR-007**: System MUST render text input with a prompt character, placeholder text, and a Send button that submits the command and appends it to the log.
- **FR-008**: System MUST render suggestion chips below the input that, when clicked, submit the chip text as a command.
- **FR-009**: System MUST render a kind picker in the wizard view with options: Room, NPC, Item, Quest, Spell.
- **FR-010**: System MUST progressively reveal interpreted data card fields based on prompt text length.
- **FR-011**: System MUST render trigger compact cards showing intent and action count, expandable into a detail modal.
- **FR-012**: System MUST render trigger detail modals with: intent selection, conditions editor (numbered rows with subject/operator/value), note, and ordered action list.
- **FR-013**: System MUST render adjective chips (removable, with "+ add" button) on Item and NPC editors for target disambiguation.
- **FR-014**: System MUST hide the "As player would see it" panel for Quest content type and expand the data card to fill available space.
- **FR-015**: System MUST support three player layout variants: classic (two-column), panels (three-column with map), and minimal (single-column centered).
- **FR-016**: System MUST support three color themes (phosphor, paper, dusk) and two density modes (comfortable, compact).
- **FR-017**: System MUST render a simulated streaming text response when the player types a trigger command (e.g., "read letter"), revealing characters progressively with a blinking cursor.
- **FR-018**: System MUST use mocked/static data for all content — no backend data persistence is required for this feature.
- **FR-019**: System MUST render all views as Phoenix LiveView controls using HEEx templates and Tailwind CSS with custom CSS variables for theming.
- **FR-020**: Modals MUST close when the user presses Escape or clicks the backdrop overlay.
- **FR-021**: System MUST render NPC stats as grid cells (HP/MP as max-only values, ability scores with modifiers) and loot as rows with percentage drop chances.
- **FR-022**: System MUST render quest steps as numbered cards with IDs and descriptions, and rewards as typed rows (item with ID, XP, faction).
- **FR-023**: System MUST auto-update the wizard starter prompt when switching content kinds (unless the user has manually edited the text).

### Key Entities

- **Log Entry**: A single entry in the narrative text log. Types: room, narrate, command, dialogue, whisper, system, combat. Each type has distinct visual rendering.
- **Room**: A location in the game world with name, coordinate, description, exits (directional), and entities (NPCs, items, other players).
- **HUD Card**: A collapsible panel in the player sidebar (Character, Inventory, Quest Log, Present) that expands to a detail modal on click.
- **Item**: A game object with name, pickable flag, short description, long description, adjectives, and optional triggers.
- **NPC**: A non-player character with name, short/long descriptions, adjectives, level, HP/MP stats, ability scores, loot table, and optional triggers.
- **Quest**: A player objective with giver, goal, ordered steps (each with ID and description), and typed rewards (item, XP, faction).
- **Trigger**: A behavioral rule with intent (e.g., Use, Take, Whisper), conditions (subject/operator/value triples that all must be true), a note, and ordered actions (typed steps like emit_text, modify_prop, spawn_entity, etc.). No explicit target field — the owning entity is the implicit target.
- **Tweaks**: User preferences for theme (phosphor/paper/dusk), density (comfortable/compact), player layout (classic/panels/minimal), wizard preview default (card/ingame), and HUD visibility.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Both Player and Wizard views render correctly with all mocked data visible and no visual errors on initial page load.
- **SC-002**: Users can switch between Player and Wizard modes with a single click, and the view transitions immediately.
- **SC-003**: All four HUD card modals (Character, Inventory, Quest Log, Present) open within 200ms of clicking the card header and display complete mock data.
- **SC-004**: The wizard interpreted data card reveals fields progressively as the prompt grows, with no jarring layout shifts.
- **SC-005**: Trigger compact cards and detail modals render all data (intent, conditions, actions) accurately for all content types that have triggers.
- **SC-006**: All three player layout variants (classic, panels, minimal) produce visually correct grid arrangements without overlapping or clipped content.
- **SC-007**: All three color themes (phosphor, paper, dusk) apply consistently across both Player and Wizard views without broken contrast or missing variable bindings.
- **SC-008**: The map toggle button correctly shows and hides the mini-map panel across all layout variants that support it.
- **SC-009**: Simulated streaming text responses render character-by-character with a visible blinking cursor, completing within 3 seconds.
- **SC-010**: 100% of UI controls are implemented as Phoenix LiveView components using HEEx templates — no inline scripts or external JS framework dependencies.

## Assumptions

- This feature establishes the UI foundation only. All data is mocked and static — no database, backend logic, or real-time communication is wired up.
- The application uses Phoenix 1.8 with LiveView, Tailwind CSS v4, and follows the project's AGENTS.md guidelines for HEEx templates, component patterns, and JS interop.
- The "terminal revival" design aesthetic (dark backgrounds, monospace fonts, phosphor green/amber accents) is derived from the Claude Design prototype and will be implemented using CSS custom properties for theming.
- Font families (JetBrains Mono, IBM Plex Mono, Fraunces) will be loaded via the app.css bundle — no external CDN links.
- The Spell content kind in the wizard view is listed in the kind picker but does not need a full example data set for this initial feature — a minimal placeholder is sufficient.
- Interactive behaviors (command submission, streaming text, modal open/close, kind switching, map toggle) are implemented as LiveView event handlers with mocked responses — no AI/LLM integration.
- Mobile/responsive layouts are out of scope for this initial feature.
