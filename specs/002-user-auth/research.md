# Research: Player Authentication & Account Management

**Feature**: 002-user-auth  
**Date**: 2026-04-23

## Authentication Approach

**Decision**: Manual Plug-based authentication following `mix phx.gen.auth` patterns

**Rationale**: The Phoenix framework provides well-documented patterns for session-based authentication using Plug. Since the requirements are straightforward (username + password, no OAuth/SSO, no email), a manual implementation following `phx.gen.auth` conventions gives full control without unnecessary abstractions. The user explicitly requested Ecto persistence for the Player entity and stated sessions don't need persistence.

**Alternatives considered**:
- `mix phx.gen.auth`: Auto-generates auth scaffolding. Rejected because it generates email-based auth with confirmation tokens, password reset, and "remember me" functionality — all out of scope. The generated code would need significant trimming and modification. However, the *patterns* it establishes are exactly what we follow.
- Guardian / Pow: Third-party auth libraries. Rejected for adding unnecessary dependencies for a simple username/password flow. These libraries are better suited for JWT-based APIs or multi-provider auth.
- Ueberauth: OAuth/SSO framework. Explicitly out of scope per spec assumptions.

## Password Hashing Library

**Decision**: `bcrypt_elixir ~> 3.0`

**Rationale**: bcrypt is the industry standard for password hashing in Phoenix applications. It's the default choice in `phx.gen.auth`, well-maintained by the Comeonin project, and provides the right balance of security and performance for a web application.

**Alternatives considered**:
- `argon2_elixir`: More modern algorithm (Argon2id), winner of the Password Hashing Competition. Slightly better security properties but requires more system resources and a C compiler. Overkill for this use case.
- `pbkdf2_elixir`: Pure Elixir implementation, no native dependency. Slower and less commonly used in the Phoenix ecosystem.

## Session Strategy

**Decision**: Cookie-based sessions via `Plug.Session` (already configured in the Phoenix endpoint)

**Rationale**: The user explicitly stated "sessions do not need to be persisted and it is okay if sessions are lost during a crash." Cookie-based sessions are the Phoenix default, require zero additional infrastructure, and satisfy this requirement perfectly. The player ID is stored in the session cookie, and the player record is loaded from the database on each request via the `fetch_current_player` plug.

**Alternatives considered**:
- ETS-based sessions: Server-side session store. Faster lookups but sessions are lost on server restart — which the user said is acceptable, but this adds complexity for no benefit over cookies.
- Redis/database sessions: Persistent server-side sessions. Explicitly unnecessary per user requirements.

## Login Mechanism (LiveView vs Controller)

**Decision**: Login form submits via POST to a controller action, not a LiveView event

**Rationale**: This is the standard Phoenix pattern established by `phx.gen.auth`. LiveView events operate over WebSocket, which does not have direct access to `Plug.Session` to set session cookies. A controller POST properly sets the session cookie via `Plug.Conn`, then redirects. Registration also follows this pattern — the LiveView validates the form, then the final submission goes through a controller or uses `Plug.Conn` operations in the LiveView's `handle_event` after redirecting through a controller route.

Note: Phoenix LiveView 1.1+ provides `redirect/2` from LiveViews which can redirect to a controller route that handles the session setup. Registration can work as: LiveView validates → on success, creates the player → redirects to a session controller route that logs them in.

## Route Structure

**Decision**: Five primary routes with public/authenticated scopes

| Route | Access | LiveView/Controller |
|-------|--------|---------------------|
| `/` | Public | LandingLive |
| `/login` | Public (redirect if auth'd) | PlayerLoginLive |
| `/register` | Public (redirect if auth'd) | PlayerRegistrationLive |
| `/play` | Authenticated only | GameLive |
| `/settings` | Authenticated only | PlayerSettingsLive |

**Rationale**: Moving the game from `/` to `/play` makes the landing page the natural entry point. The route names are intuitive and follow web conventions. Public auth routes redirect already-authenticated players to prevent confusion.

## LiveView Authentication (on_mount)

**Decision**: Use `on_mount` hooks in `live_session` blocks to assign `current_player` to socket

**Rationale**: Phoenix LiveView's `live_session` with `on_mount` is the standard way to share authentication state across LiveViews. The `on_mount` hook reads the player ID from the session (passed from the Plug pipeline), loads the player from the database, and assigns it to the socket. This runs on both the initial HTTP request and the WebSocket connection.

Two `on_mount` hooks:
- `:ensure_authenticated` — loads player, halts with redirect to `/login` if not found
- `:redirect_if_authenticated` — loads player, redirects to `/` if found (for login/register pages)
