# Quickstart: GUI Design Language

**Feature**: 001-gui-design-language  
**Branch**: `001-gui-design-language`

## Prerequisites

- Elixir 1.15+
- PostgreSQL running (for Phoenix default setup)
- Node.js (for esbuild/tailwind asset compilation)

## Setup

```bash
cd /Users/kevin/code/autodidaddict/agentic-realms
mix setup
```

## Run Development Server

```bash
mix phx.server
```

Visit `http://localhost:4000` in your browser.

## Key Files (Implementation)

### LiveView
- `lib/agenticrealms_web/live/game_live.ex` — Main LiveView (mount, events, mode switching)
- `lib/agenticrealms_web/live/game_live.html.heex` — Main template (delegates to player/wizard)

### Components
- `lib/agenticrealms_web/components/game_components.ex` — All game UI function components
- `lib/agenticrealms_web/components/game_components/` — HEEx templates for game components (if split)

### Mock Data
- `lib/agenticrealms/game_data.ex` — Static game data (rooms, stats, inventory, quests, wizard examples)

### Styles
- `assets/css/game.css` — Game-specific CSS (custom properties, themes, layout, components)
- `assets/css/app.css` — Imports game.css alongside Tailwind

### Fonts
- `priv/static/fonts/` — Self-hosted web fonts (JetBrains Mono, IBM Plex Mono, Fraunces)

### Routes
- `lib/agenticrealms_web/router.ex` — Add `live "/", GameLive` route

## Design Reference

The original design prototype is at:
- `/tmp/agentic-realms-design/agentic-realms/project/Agentic Realms.html` (main HTML)
- `/tmp/agentic-realms-design/agentic-realms/project/styles.css` (CSS reference)
- `/tmp/agentic-realms-design/agentic-realms/project/src/` (component reference: app.jsx, player.jsx, wizard.jsx, data.jsx, tweaks.jsx)

## Verification

After implementation, verify:

1. `mix compile --warnings-as-errors` — No compilation warnings
2. `mix format` — Code is formatted
3. `mix test` — Tests pass
4. Browser: `http://localhost:4000` renders the player view with all mocked data
5. Browser: clicking "Wizard" in topbar switches to wizard view
6. Browser: all three themes (phosphor/paper/dusk) apply correctly
