# Research: GUI Design Language

**Feature**: 001-gui-design-language  
**Date**: 2026-04-22

## R1: Routing Architecture — Single LiveView vs Multiple

**Decision**: Single LiveView (`GameLive`) with mode toggle via assigns.

**Rationale**: The design prototype uses a single HTML file with client-side mode switching (Player/Wizard via a pill toggle in the topbar). A single LiveView with `@mode` assign mirrors this 1:1. Mode switching via `handle_event` is instant (no navigation, no mount cycle). All mock data is loaded once in `mount/3`.

**Alternatives considered**:
- Separate LiveViews (`PlayerLive`, `WizardLive`) with `push_navigate` — adds unnecessary mount overhead, duplicates topbar/theme state, and complicates shared tweaks state. Rejected.
- Separate routes with `live_session` — overcomplicated for a UI prototype with no auth or persistence. Rejected.

## R2: CSS Integration Strategy

**Decision**: Add game-specific CSS custom properties and `@font-face` rules directly in `assets/css/app.css` after the existing Tailwind/daisyUI imports. Use a dedicated `assets/css/game.css` file imported into `app.css` for the bulk of the game-specific styles.

**Rationale**: Tailwind v4 supports standard CSS alongside `@import` directives. The existing app.css already defines custom properties via daisyUI plugins. The design's CSS variables (`--bg`, `--ink`, `--player`, `--wizard`, etc.) and theme variants (`[data-theme="phosphor"]`, etc.) are standard CSS that coexist with Tailwind utility classes. Separating into `game.css` keeps concerns clean.

**Alternatives considered**:
- Inline all styles as Tailwind utilities — impractical; the design has ~2200 lines of purpose-built CSS with oklch colors, complex grid layouts, and animation keyframes that don't map cleanly to utilities. Rejected.
- Tailwind `@theme` extension — viable for variables but doesn't cover the layout/component-specific CSS. Partial use acceptable.

## R3: Font Loading Strategy

**Decision**: Self-host fonts in `priv/static/fonts/`. Define `@font-face` rules in `assets/css/game.css`. Load three families: JetBrains Mono (UI), IBM Plex Mono (body text), Fraunces (serif accents).

**Rationale**: The AGENTS.md states "Only the app.js and app.css bundles are supported — You cannot reference an external vendor'd script src or link href in the layouts." Self-hosting avoids CDN dependencies and complies with this constraint. The `static_paths` in `agenticrealms_web.ex` already includes `fonts`.

**Alternatives considered**:
- Google Fonts CDN via `<link>` tag — violates AGENTS.md constraint on external resources. Rejected.
- Fontsource npm packages — adds npm dependency; self-hosting is simpler. Rejected.

## R4: Mock Data Architecture

**Decision**: Create `AgenticRealms.GameData` module with functions returning static data structures. Call these functions in `GameLive.mount/3` and assign results to socket.

**Rationale**: The user explicitly stated "Mock the data in the views rather than in the html heex templates." Data in an Elixir module is testable, reusable, and keeps templates clean. Maps and keyword lists translate directly from the design's JavaScript data objects.

**Alternatives considered**:
- Hardcoded assigns directly in `mount/3` — messy for the volume of data (rooms, stats, inventory, quests, wizard examples). Extracted module is cleaner. Rejected.
- JSON files loaded at compile time — unnecessary complexity. Rejected.

## R5: Component Architecture

**Decision**: Use function components (not LiveComponents) organized in a `GameComponents` module. Keep `CoreComponents` for standard Phoenix controls. Import `GameComponents` into `html_helpers/0` in `agenticrealms_web.ex` so all game components are available everywhere.

**Rationale**: AGENTS.md says "Avoid LiveComponent's unless you have a strong, specific need for them." All game UI is driven by parent assigns — no independent state needed. Function components are simpler, faster, and align with Phoenix conventions.

**Alternatives considered**:
- LiveComponents for modals/trigger editor — unnecessary; modals are controlled by parent assigns (`@modal`), not independent state. Rejected.
- Splitting into many component modules — over-engineered for a prototype. One `GameComponents` module is sufficient. Rejected.

## R6: Theme System Integration

**Decision**: Use `data-theme` attribute on `<html>` element with CSS custom properties, matching the existing Phoenix theme toggle pattern. Replace the default light/dark/system themes with phosphor/paper/dusk. Theme switching via LiveView `handle_event` that dispatches a JS command to set `data-theme`.

**Rationale**: The root layout already has a `data-theme` attribute system with localStorage persistence. The design's theme system (phosphor/paper/dusk) maps cleanly onto this pattern. CSS custom properties defined under `[data-theme="phosphor"]`, etc. override the `:root` defaults.

**Alternatives considered**:
- Server-side theme rendering via assigns — would cause full re-render on theme change. Client-side `data-theme` is instant. Rejected.

## R7: Streaming Text Animation

**Decision**: Use a colocated JS hook (`.StreamingText`) with `phx-hook=".StreamingText"` for character-by-character text reveal. The hook receives the full text via `push_event` and animates locally.

**Rationale**: AGENTS.md supports colocated hooks (names prefixed with `.`). Character-by-character animation at 14ms intervals requires client-side timing — LiveView's server round-trip latency would make server-driven streaming janky. The hook pattern is explicitly documented in AGENTS.md.

**Alternatives considered**:
- Server-side streaming with `send_after` — too slow for 5-chars-per-14ms animation; each update would require a websocket round-trip. Rejected.
- CSS animation only — cannot animate text content reveal character-by-character. Rejected.

## R8: daisyUI Usage

**Decision**: Do not use daisyUI classes for game components. The game has its own complete design language. daisyUI may remain installed for any non-game pages but should not be used in game views.

**Rationale**: AGENTS.md explicitly says "Always manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design." The design prototype has a complete CSS system with no daisyUI dependency.

**Alternatives considered**:
- Remove daisyUI entirely — would break existing core_components.ex which uses daisyUI classes. Keep it but don't use it in game views. Selected hybrid approach.
