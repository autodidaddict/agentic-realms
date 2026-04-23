# Quickstart: Player Authentication & Account Management

**Feature**: 002-user-auth  
**Date**: 2026-04-23

## Prerequisites

- Elixir 1.15+ and Erlang OTP 26+ installed
- PostgreSQL running locally
- Project dependencies installed (`mix deps.get`)
- Database created (`mix ecto.create`)

## Setup Steps

### 1. Install new dependency

After adding `bcrypt_elixir` to `mix.exs`:

```bash
mix deps.get
```

### 2. Run database migration

```bash
mix ecto.migrate
```

This creates the `players` table with `username`, `hashed_password`, and timestamps.

### 3. Start the development server

```bash
mix phx.server
```

### 4. Verify the feature

1. **Landing page**: Visit `http://localhost:4000/` — you should see the hero image, game description, and "Log In" / "Create Account" links.

2. **Registration**: Click "Create Account", enter a username (3-30 alphanumeric/hyphens/underscores) and password (min 8 chars), confirm password, submit. You should be logged in and redirected to the landing page with the authenticated nav bar.

3. **Navigation**: The nav bar should show a home icon, "Play" link, and your username in the top right. Click "Play" to reach the game screen. The Player/Wizard mode switch should appear in the game content area (not in the nav bar).

4. **Profile settings**: Click your username → "Settings". Try changing your username or password. Try the account deletion flow (requires typing your username to confirm).

5. **Logout**: Click your username → "Log Out". You should be redirected to the landing page as an unauthenticated visitor.

6. **Auth protection**: Try navigating directly to `http://localhost:4000/play` without logging in — you should be redirected to `/login`.

## Running Tests

```bash
mix test
```

Or run only auth-related tests:

```bash
mix test test/agenticrealms/accounts_test.exs
mix test test/agenticrealms_web/live/player_registration_live_test.exs
mix test test/agenticrealms_web/live/player_login_live_test.exs
mix test test/agenticrealms_web/live/player_settings_live_test.exs
mix test test/agenticrealms_web/live/landing_live_test.exs
mix test test/agenticrealms_web/controllers/player_session_controller_test.exs
```

## Full pre-commit check

```bash
mix precommit
```

This runs formatting, compilation warnings check, and the full test suite.
