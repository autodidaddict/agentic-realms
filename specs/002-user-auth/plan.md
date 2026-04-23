# Implementation Plan: Player Authentication & Account Management

**Branch**: `002-user-auth` | **Date**: 2026-04-23 | **Spec**: [spec.md](spec.md)  
**Input**: Feature specification from `specs/002-user-auth/spec.md`

## Summary

Add player authentication and account management to the Agentic Realms Phoenix application. Players register with a username and password, log in via session-based auth, and can modify their profile or delete their account. The landing page becomes the public entry point with a hero image and game description. All other routes (except login and registration) require authentication. A new top navigation bar replaces the existing game topbar, with a home icon, "Play" link, and a username dropdown (Settings, Log Out). The Player/Wizard mode switch moves into the game screen content area.

**User constraints**:
- Player entity persisted through Ecto (standard Phoenix auth pattern)
- Sessions do not need to be persisted; in-memory/cookie sessions are acceptable
- Session loss on crash is acceptable

## Technical Context

**Language/Version**: Elixir 1.15+ / Erlang OTP 26+  
**Primary Dependencies**: Phoenix 1.8.5, Phoenix LiveView 1.1.0, Ecto 3.13, bcrypt_elixir ~> 3.0  
**Storage**: PostgreSQL (Ecto Repo already configured, no existing migrations)  
**Testing**: ExUnit + Phoenix.ConnTest + Phoenix.LiveViewTest  
**Target Platform**: Web browser (desktop only, no mobile)  
**Project Type**: Web application (Phoenix LiveView)  
**Performance Goals**: Registration/login forms render instantly; auth checks add negligible overhead  
**Constraints**: Cookie-based sessions (no server-side session store needed); no external auth providers  
**Scale/Scope**: 1 new Ecto schema (Player), 1 migration, ~6 new LiveViews/controllers, updated navigation across all views

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution is a template (not yet ratified for this project). No gates to enforce. Proceeding.

**Post-Phase 1 re-check**: No violations. The design uses standard Phoenix auth patterns (Ecto schema, bcrypt, Plug sessions), minimal new modules, and follows project conventions from AGENTS.md.

## Project Structure

### Documentation (this feature)

```text
specs/002-user-auth/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: technical decisions
├── data-model.md        # Phase 1: entity definitions
├── quickstart.md        # Phase 1: setup guide
├── contracts/
│   └── routes.md        # Phase 1: route/page contracts
└── checklists/
    └── requirements.md  # Specification quality checklist
```

### Source Code (repository root)

```text
lib/
├── agenticrealms/
│   ├── accounts.ex                    # NEW: Accounts context (CRUD, auth logic)
│   ├── accounts/
│   │   └── player.ex                  # NEW: Player Ecto schema + changeset
│   ├── game_data.ex                   # existing (unchanged)
│   └── repo.ex                        # existing (unchanged)
└── agenticrealms_web/
    ├── components/
    │   ├── core_components.ex         # existing (unchanged)
    │   ├── game_components.ex         # MODIFIED: remove topbar, relocate mode switch
    │   ├── layouts.ex                 # MODIFIED: new authenticated nav bar layout
    │   └── layouts/
    │       └── root.html.heex         # existing (unchanged)
    ├── controllers/
    │   └── player_session_controller.ex # NEW: login/logout POST handlers
    ├── live/
    │   ├── game_live.ex               # MODIFIED: remove topbar render, add mode switch inline
    │   ├── game_live.html.heex        # MODIFIED: topbar → inline mode switch
    │   ├── player_registration_live.ex # NEW: registration form LiveView
    │   ├── player_login_live.ex       # NEW: login form LiveView
    │   ├── player_settings_live.ex    # NEW: profile settings LiveView
    │   └── landing_live.ex            # NEW: public landing page LiveView
    ├── player_auth.ex                 # NEW: auth plugs (fetch_current_player, require_auth, redirect_if_authenticated)
    └── router.ex                      # MODIFIED: public/authenticated scopes, live_sessions

priv/
└── repo/
    └── migrations/
        └── YYYYMMDDHHMMSS_create_players.exs  # NEW: players table migration

test/
├── agenticrealms/
│   └── accounts_test.exs             # NEW: context unit tests
└── agenticrealms_web/
    ├── controllers/
    │   └── player_session_controller_test.exs  # NEW
    └── live/
        ├── player_registration_live_test.exs   # NEW
        ├── player_login_live_test.exs          # NEW
        ├── player_settings_live_test.exs       # NEW
        └── landing_live_test.exs               # NEW
```

**Structure Decision**: Standard Phoenix web application structure following `mix phx.gen.auth` conventions. The auth feature adds an Accounts context with a Player schema, auth plugs, session controller, and LiveViews for registration/login/settings. The existing game LiveView moves behind an authenticated `live_session`.

## Implementation Phases

### Phase A: Dependencies & Database Schema

**Goal**: Add the password hashing dependency, create the Player schema and migration.

1. **Add `bcrypt_elixir` to `mix.exs`**:
   - `{:bcrypt_elixir, "~> 3.0"}`
   - Run `mix deps.get`

2. **Create the Player schema** at `lib/agenticrealms/accounts/player.ex`:
   - Fields: `username` (string, unique), `hashed_password` (string), `timestamps()`
   - Registration changeset: validates username format (alphanumeric, hyphens, underscores, 3-30 chars), uniqueness, password length (min 8), hashes password
   - Profile changeset: validates username changes (same rules)
   - Password changeset: validates current password, hashes new password

3. **Create the migration** at `priv/repo/migrations/YYYYMMDDHHMMSS_create_players.exs`:
   - `username`: string, not null
   - `hashed_password`: string, not null
   - Unique index on `username`
   - Timestamps

4. **Run `mix ecto.create && mix ecto.migrate`**

### Phase B: Accounts Context

**Goal**: Build the business logic layer for player CRUD and authentication.

1. **Create `lib/agenticrealms/accounts.ex`**:
   - `register_player(attrs)` — creates a new player with hashed password
   - `get_player!(id)` — fetches player by ID (raises on not found)
   - `get_player_by_username(username)` — fetches player by username
   - `get_player_by_username_and_password(username, password)` — authenticates
   - `change_player_registration(player, attrs)` — returns changeset for registration form
   - `change_player_username(player, attrs)` — returns changeset for username update
   - `update_player_username(player, attrs)` — applies username change
   - `change_player_password(player, attrs)` — returns changeset for password change
   - `update_player_password(player, current_password, attrs)` — validates current password, applies change
   - `delete_player(player)` — permanently deletes the player record

2. **Write unit tests** at `test/agenticrealms/accounts_test.exs`:
   - Test registration with valid/invalid data
   - Test authentication (valid creds, invalid creds)
   - Test username update (valid, duplicate)
   - Test password update (valid, wrong current password)
   - Test player deletion

### Phase C: Authentication Plugs & Session Controller

**Goal**: Wire up session-based authentication using Plug.

1. **Create `lib/agenticrealms_web/player_auth.ex`**:
   - `fetch_current_player/2` plug — reads player ID from session, loads player into `conn.assigns.current_player`
   - `require_authenticated_player/2` plug — redirects to login if no current player
   - `redirect_if_player_is_authenticated/2` plug — redirects authenticated players away from login/register
   - `log_in_player/2` — puts player ID in session, renews session token (CSRF protection)
   - `log_out_player/1` — clears session, redirects to landing page

2. **Create `lib/agenticrealms_web/controllers/player_session_controller.ex`**:
   - `create/2` — authenticates player, calls `log_in_player`
   - `delete/2` — calls `log_out_player`

3. **Write controller tests**

### Phase D: Router & Route Structure

**Goal**: Set up public and authenticated route scopes.

1. **Update `lib/agenticrealms_web/router.ex`**:
   - Add `player_auth.ex` plugs to the browser pipeline:
     - `:fetch_current_player` in the main browser pipeline
   - Public scope (redirect if authenticated):
     - `live "/login", PlayerLoginLive`
     - `live "/register", PlayerRegistrationLive`
     - `post "/login", PlayerSessionController, :create`
   - Public scope (no redirect):
     - `live "/", LandingLive`
   - Authenticated scope (`require_authenticated_player`):
     - `live "/play", GameLive`
     - `live "/settings", PlayerSettingsLive`
     - `delete "/logout", PlayerSessionController, :delete`

2. **Wrap authenticated routes in `live_session`** with `on_mount` hook that checks session for the current player and assigns it to the socket.

### Phase E: Landing Page & Public LiveViews

**Goal**: Build the landing page and auth forms.

1. **Create `lib/agenticrealms_web/live/landing_live.ex`**:
   - Renders hero image and game description
   - If `@current_player` is nil: show "Log In" and "Create Account" links
   - If `@current_player` is set: show authenticated nav bar (handled by layout)

2. **Create `lib/agenticrealms_web/live/player_registration_live.ex`**:
   - Form with username, password, password confirmation fields
   - Validates on change (inline errors)
   - On submit: calls `Accounts.register_player/1`, then `log_in_player`
   - Styled to match the terminal-revival design language

3. **Create `lib/agenticrealms_web/live/player_login_live.ex`**:
   - Form with username and password fields
   - Posts to `PlayerSessionController.create` (standard Phoenix pattern — login uses a controller POST, not a LiveView event, to properly set the session)
   - Styled to match the terminal-revival design language

4. **Write LiveView tests** for landing, registration, and login

### Phase F: Navigation Bar & Layout Updates

**Goal**: Replace the existing game topbar with the new authenticated navigation bar.

1. **Update `lib/agenticrealms_web/components/layouts.ex`**:
   - Modify the `app/1` layout to render the authenticated navigation bar when `@current_player` is present:
     - Top left: home icon (links to `/`)
     - Center/left: "Play" link (links to `/play`)
     - Top right: username text that toggles a dropdown with "Settings" (links to `/settings`) and "Log Out" (posts to `/logout`)
   - When `@current_player` is nil: render unauthenticated links (Log In, Create Account)

2. **Update `lib/agenticrealms_web/components/game_components.ex`**:
   - Remove the `topbar/1` component entirely
   - The Player/Wizard mode switch moves into the game view content area

3. **Update `lib/agenticrealms_web/live/game_live.html.heex`**:
   - Remove `<.topbar>` call
   - Add inline mode switch (Player/Wizard pills) at the top of the game content area, below where the nav bar renders from the layout

4. **Update `lib/agenticrealms_web/live/game_live.ex`**:
   - Ensure the game layout includes the nav bar (switch from `game` layout to `app` layout, or update `game` layout to include nav)

### Phase G: Player Settings LiveView

**Goal**: Build the profile management page.

1. **Create `lib/agenticrealms_web/live/player_settings_live.ex`**:
   - Two forms: username change, password change
   - Username form: shows current username, validates on change, saves on submit
   - Password form: current password, new password, confirm new password
   - Account deletion section at bottom:
     - "Delete Account" button triggers a confirmation modal
     - Modal warns action is permanent
     - Requires typing username to confirm
     - On confirm: calls `Accounts.delete_player/1`, then `log_out_player`
   - Styled to match the terminal-revival design language

2. **Write LiveView tests** for all settings actions

### Phase H: Testing & Integration

**Goal**: Verify all auth flows work end-to-end and existing game functionality is preserved.

1. **Write integration tests**:
   - Unauthenticated access to `/play` redirects to `/login`
   - Unauthenticated access to `/settings` redirects to `/login`
   - Authenticated access to `/login` redirects to `/`
   - Full registration → login → play → settings → logout flow
   - Account deletion flow

2. **Run `mix precommit`** to verify:
   - No compilation warnings
   - Code formatted
   - All tests pass (existing game_live tests + new auth tests)

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Auth approach | Manual (Plug-based, following `phx.gen.auth` patterns) | Standard Phoenix approach; no external auth library needed for username/password |
| Password hashing | bcrypt_elixir | Industry standard, recommended by Phoenix team |
| Session storage | Cookie-based (Plug.Session) | User explicitly stated sessions don't need persistence; crash loss acceptable |
| Login mechanism | Controller POST (not LiveView event) | Standard Phoenix pattern — POST to controller sets session cookie properly |
| Player schema | Ecto schema in Accounts context | User explicitly requested Ecto persistence; follows Phoenix conventions |
| Nav bar location | In layout (`app/1`) | Consistent across all authenticated pages; single source of truth |
| Mode switch relocation | Inline in game content area | Per spec clarification — stays close to the game UI, nav bar is for app navigation |
| Route structure | `/` landing, `/login`, `/register`, `/play`, `/settings` | Clear separation of public vs. authenticated; game moves from `/` to `/play` |
| Account deletion | Two-step: warning dialog + type username | Per spec FR-011; prevents accidental deletion |

## Complexity Tracking

No constitution violations to justify — the design follows standard Phoenix auth patterns:
- 1 Ecto schema, 1 context, 1 auth module, 1 controller, 4 LiveViews
- No external auth services, no complex session stores, no role-based access
