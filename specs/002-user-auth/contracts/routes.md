# Route & Page Contracts: Player Authentication & Account Management

**Feature**: 002-user-auth  
**Date**: 2026-04-23

## Route Map

### Public Routes

| Method | Path | Handler | Description |
|--------|------|---------|-------------|
| GET | `/` | `LandingLive` | Home landing page (hero image, game description) |
| GET | `/login` | `PlayerLoginLive` | Login form (redirects to `/` if already authenticated) |
| GET | `/register` | `PlayerRegistrationLive` | Registration form (redirects to `/` if already authenticated) |
| POST | `/login` | `PlayerSessionController.create` | Authenticate and create session |

### Authenticated Routes

| Method | Path | Handler | Description |
|--------|------|---------|-------------|
| GET | `/play` | `GameLive` | Game screen (Player/Wizard views from 001 spec) |
| GET | `/settings` | `PlayerSettingsLive` | Profile settings (username, password, delete account) |
| DELETE | `/logout` | `PlayerSessionController.delete` | End session, redirect to `/` |

## Page Contracts

### Landing Page (`/`)

**LiveView**: `LandingLive`  
**Layout**: `app` (renders nav bar based on auth state)

**Unauthenticated state**:
- Hero image (static asset, full-width or prominent placement)
- Game description text (what Agentic Realms is)
- "Log In" link → `/login`
- "Create Account" link → `/register`

**Authenticated state**:
- Same hero image and game description
- Authenticated navigation bar (from layout):
  - Top left: home icon (active state, since we're on home)
  - "Play" link → `/play`
  - Top right: username dropdown → "Settings" (`/settings`), "Log Out" (`DELETE /logout`)

### Login Page (`/login`)

**LiveView**: `PlayerLoginLive`  
**Access**: Public only (redirects to `/` if authenticated)

**Content**:
- Form with fields:
  - Username (text input, required)
  - Password (password input, required)
- Submit button: "Log In"
- Link to registration: "Don't have an account? Create one" → `/register`
- Error display: generic "Invalid username or password" on failure
- Form action: POST to `/login` (controller handles session)

### Registration Page (`/register`)

**LiveView**: `PlayerRegistrationLive`  
**Access**: Public only (redirects to `/` if authenticated)

**Content**:
- Form with fields:
  - Username (text input, required, validates on change: format, length, uniqueness)
  - Password (password input, required, validates on change: min length)
  - Password confirmation (password input, required, validates match)
- Submit button: "Create Account"
- Link to login: "Already have an account? Log in" → `/login`
- Error display: inline field errors on validation failure
- On success: creates player, logs in, redirects to `/`

### Game Screen (`/play`)

**LiveView**: `GameLive` (existing, modified)  
**Access**: Authenticated only (redirects to `/login` if not)  
**Layout**: `app` (authenticated nav bar)

**Changes from 001 spec**:
- Old topbar component removed
- Authenticated nav bar rendered by layout (home icon, "Play" active, username dropdown)
- Player/Wizard mode switch rendered inline at top of game content area (below nav bar)
- All existing game functionality preserved

### Settings Page (`/settings`)

**LiveView**: `PlayerSettingsLive`  
**Access**: Authenticated only (redirects to `/login` if not)

**Content**:
- **Username section**:
  - Shows current username
  - Form to change username (validates format, length, uniqueness on change)
  - Save button
  - Success/error feedback

- **Password section**:
  - Form with current password, new password, confirm new password
  - Save button
  - Success/error feedback

- **Danger zone** (visually distinct, bottom of page):
  - "Delete Account" button (styled as destructive action)
  - On click: opens confirmation modal
  - Modal content:
    - Warning text: "This action is permanent and cannot be undone"
    - Text input: "Type your username to confirm"
    - "Delete" button (disabled until username matches)
    - "Cancel" button
  - On confirm: deletes player, clears session, redirects to `/`

## Navigation Bar Contract

### Authenticated Navigation Bar

Rendered by the `app/1` layout when `@current_player` is assigned.

```
┌──────────────────────────────────────────────────────────┐
│ 🏠  Home    Play                          [username ▾]  │
│                                            ├─ Settings  │
│                                            └─ Log Out   │
└──────────────────────────────────────────────────────────┘
```

- **Home icon** (top left): Heroicon `home`, links to `/`
- **"Play"** link: links to `/play`
- **Username dropdown** (top right): displays `@current_player.username`
  - Clicking toggles a dropdown menu
  - "Settings" → `/settings`
  - "Log Out" → `DELETE /logout` (via button with `method: :delete`)

### Unauthenticated State

When `@current_player` is nil (on landing page):

```
┌──────────────────────────────────────────────────────────┐
│ Agentic Realms                      Log In | Create Acct │
└──────────────────────────────────────────────────────────┘
```

- **Branding** (left): "Agentic Realms" text
- **Links** (right): "Log In" → `/login`, "Create Account" → `/register`

## Authentication Flow

### Login Flow
```
Visitor → GET /login → Fill form → POST /login → Controller authenticates
  → Success: set session, redirect to /
  → Failure: redirect back to /login with error flash
```

### Registration Flow
```
Visitor → GET /register → Fill form (validates on change) → Submit
  → LiveView creates player via Accounts context
  → Success: redirect to POST /login controller to set session → redirect to /
  → Failure: show inline errors
```

### Logout Flow
```
Player → Click "Log Out" in dropdown → DELETE /logout → Controller clears session → redirect to /
```

### Account Deletion Flow
```
Player → GET /settings → Click "Delete Account" → Modal appears
  → Type username → Click "Delete" → LiveView deletes player, clears session → redirect to /
```
