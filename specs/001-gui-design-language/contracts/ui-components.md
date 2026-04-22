# UI Component Contracts: GUI Design Language

**Feature**: 001-gui-design-language  
**Date**: 2026-04-22

## LiveView

### GameLive

**Module**: `AgenticRealmsWeb.GameLive`  
**Route**: `live "/", GameLive`

#### Assigns (set in mount)

| Assign | Type | Default | Description |
|--------|------|---------|-------------|
| `mode` | atom | `:player` | Current view mode (`:player` or `:wizard`) |
| `modal` | atom/nil | `nil` | Active modal (`:stats`, `:inv`, `:quests`, `:presence`, or `nil`) |
| `map_open` | boolean | `false` | Whether mini-map panel is visible |
| `log` | list | starting_log() | Player narrative log entries |
| `input` | string | `""` | Player command input text |
| `streaming` | boolean | `false` | Whether a streaming response is active |
| `stats` | map | player_stats() | Player character stats |
| `inventory` | list | inventory() | Player inventory items |
| `quests` | list | quests() | Active quest summaries |
| `quest_details` | list | quest_details() | Detailed quest data for modal |
| `presence` | list | presence() | Entities present in room |
| `suggestions` | list | suggestions() | Command suggestion chips |
| `wizard_kind` | atom | `:item` | Active wizard content kind |
| `wizard_text` | string | starter_prompt(:item) | Wizard textarea content |
| `wizard_user_edited` | boolean | `false` | Whether user manually edited wizard text |
| `open_trigger` | map/nil | `nil` | Trigger currently open in detail modal |
| `tweaks` | map | default_tweaks() | Theme/layout preferences |
| `tweaks_open` | boolean | `false` | Whether tweaks panel is visible |

#### Events

| Event | Params | Description |
|-------|--------|-------------|
| `switch_mode` | `%{"mode" => "player"\|"wizard"}` | Toggle between player/wizard |
| `submit_command` | `%{"text" => string}` | Submit player command |
| `open_modal` | `%{"modal" => string}` | Open a HUD detail modal |
| `close_modal` | (none) | Close active modal |
| `toggle_map` | (none) | Toggle mini-map visibility |
| `set_wizard_kind` | `%{"kind" => string}` | Switch wizard content type |
| `update_wizard_text` | `%{"text" => string}` | Update wizard textarea |
| `open_trigger` | `%{"id" => string}` | Open trigger detail modal |
| `close_trigger` | (none) | Close trigger modal |
| `set_tweak` | `%{"key" => string, "value" => string}` | Update a tweaks preference |
| `toggle_tweaks` | (none) | Toggle tweaks panel visibility |
| `click_suggestion` | `%{"text" => string}` | Click a suggestion chip |
| `select_quest` | `%{"index" => string}` | Select quest in modal |

---

## Function Components (GameComponents)

### Topbar

```elixir
attr :mode, :atom, required: true       # :player or :wizard
attr :stats, :map, required: true        # player stats for name display
```

### Player View Components

#### player_view
```elixir
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
```

#### log_entry
```elixir
attr :entry, :map, required: true        # single log entry
```

#### hud_card
```elixir
attr :title, :string, required: true
attr :count, :string, default: nil
slot :inner_block, required: true
```

#### hp_bar
```elixir
attr :label, :string, required: true
attr :cur, :integer, required: true
attr :max, :integer, required: true
attr :kind, :string, required: true      # "hp", "mp", "xp"
```

#### mini_map
```elixir
# No attrs — uses hardcoded mock map data
```

#### stats_modal / inventory_modal / quest_modal / presence_modal
```elixir
# Each takes relevant data via assigns from parent
```

### Wizard View Components

#### wizard_view
```elixir
attr :kind, :atom, required: true
attr :text, :string, required: true
attr :tweaks, :map, required: true
attr :open_trigger, :map, default: nil
```

#### kind_picker
```elixir
attr :value, :atom, required: true       # current kind
```

#### data_card
```elixir
attr :example, :map, required: true      # WizardExample data
attr :text_length, :integer, required: true  # for progressive reveal
```

#### trigger_compact_card
```elixir
attr :trigger, :map, required: true
attr :index, :integer, required: true    # for phx-value-id
```

#### trigger_modal
```elixir
attr :trigger, :map, required: true
```

#### conditions_editor
```elixir
attr :conditions, :list, required: true
```

---

## CSS Custom Properties Contract

All game components use CSS custom properties for theming. These MUST be defined for all three themes:

### Required Variables

```css
--bg, --bg-elev, --bg-sunken, --bg-inset
--line, --line-soft
--ink, --ink-dim, --ink-faint, --ink-ghost
--player, --player-dim, --player-bg
--wizard, --wizard-dim, --wizard-bg
--danger, --mana, --xp
--mono, --prose, --serif
--pad, --gap, --radius, --radius-lg
--fs-xs, --fs-sm, --fs-base, --fs-md, --fs-lg, --fs-xl
```

### Theme Selectors

```css
:root { /* phosphor theme (default) */ }
[data-theme="paper"] { /* light theme overrides */ }
[data-theme="dusk"] { /* purple/teal theme overrides */ }
[data-density="compact"] { /* compact density overrides */ }
```

## JS Hooks Contract

### .StreamingText (Colocated Hook)

Reveals text character by character with a blinking cursor.

```javascript
// Receives: push_event("stream_text", %{text: "full text here"})
// Emits: pushEvent("stream_done", {}) when animation complete
```

### .ThemeSwitch (Colocated Hook)

Sets `data-theme` attribute on `<html>` element and persists to localStorage.

```javascript
// Receives: push_event("set_theme", %{theme: "phosphor"|"paper"|"dusk"})
```
