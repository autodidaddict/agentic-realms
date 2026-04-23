# Tasks: Player Authentication & Account Management

**Input**: Design documents from `specs/002-user-auth/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/routes.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Add dependency and create the Player database schema

- [x] T001 Add `{:bcrypt_elixir, "~> 3.0"}` to deps in `mix.exs` and run `mix deps.get`
- [x] T002 Create Player Ecto schema at `lib/agenticrealms/accounts/player.ex` with fields: username (string, unique, 3-30 chars, alphanumeric/hyphens/underscores), hashed_password (string), timestamps; include registration changeset (validates username format/uniqueness, password min 8 chars, hashes password), username changeset, and password changeset (requires current password verification)
- [x] T003 Create migration at `priv/repo/migrations/YYYYMMDDHHMMSS_create_players.exs` with username (string, not null), hashed_password (string, not null), timestamps, and unique index on username; run `mix ecto.migrate`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core authentication infrastructure that ALL user stories depend on

**Warning**: No user story work can begin until this phase is complete

- [x] T004 Create Accounts context at `lib/agenticrealms/accounts.ex` with functions: `register_player/1`, `get_player!/1`, `get_player_by_username/1`, `get_player_by_username_and_password/2`, `change_player_registration/2`, `change_player_username/2`, `update_player_username/2`, `change_player_password/2`, `update_player_password/3`, `delete_player/1`
- [x] T005 Create auth module at `lib/agenticrealms_web/player_auth.ex` with plugs: `fetch_current_player/2` (reads player_id from session, loads player into assigns), `require_authenticated_player/2` (redirects to /login if not authenticated), `redirect_if_player_is_authenticated/2` (redirects to / if authenticated); and helper functions: `log_in_player/2` (sets session, renews CSRF token), `log_out_player/1` (clears session, redirects to /); include `on_mount` callbacks `:ensure_authenticated` and `:redirect_if_authenticated` for LiveView live_sessions
- [x] T006 Create session controller at `lib/agenticrealms_web/controllers/player_session_controller.ex` with `create/2` (authenticates player, calls log_in_player) and `delete/2` (calls log_out_player)
- [x] T007 Update router at `lib/agenticrealms_web/router.ex`: add `fetch_current_player` plug to browser pipeline; create public scope with `redirect_if_player_is_authenticated` for `/login` (PlayerLoginLive), `/register` (PlayerRegistrationLive), and POST `/login` (PlayerSessionController.create); create public scope without redirect for `/` (LandingLive); create authenticated `live_session` with `on_mount: :ensure_authenticated` for `/play` (GameLive) and `/settings` (PlayerSettingsLive); add `DELETE /logout` route to PlayerSessionController.delete
- [x] T008 Update layout at `lib/agenticrealms_web/components/layouts.ex`: modify `app/1` to render authenticated nav bar when `@current_player` is present (home icon top-left linking to `/`, "Play" link to `/play`, username dropdown top-right with "Settings" linking to `/settings` and "Log Out" button posting DELETE to `/logout`); render unauthenticated links ("Log In" to `/login`, "Create Account" to `/register`) when `@current_player` is nil; style nav bar to match terminal-revival design language

**Checkpoint**: Authentication infrastructure ready — user story implementation can now begin

---

## Phase 3: User Story 3 - Visitor Views Landing Page (Priority: P1)

**Goal**: Public landing page with hero image and game description, accessible to all visitors

**Independent Test**: Load `/` without logging in; verify hero image, game description, and Log In / Create Account links are visible

### Implementation for User Story 3

- [x] T009 [US3] Create LandingLive at `lib/agenticrealms_web/live/landing_live.ex`: mount assigns current_player from socket; render hero image (static asset), game description of Agentic Realms, and conditional content based on auth state (unauthenticated: show Log In and Create Account links; authenticated: links handled by nav bar in layout); use `app` layout; style to match terminal-revival design language

**Checkpoint**: Landing page is functional — visitors see the public home page with hero and game description

---

## Phase 4: User Story 1 - Player Creates a New Account (Priority: P1)

**Goal**: New visitors can register with a username and password and are automatically logged in

**Independent Test**: Navigate to `/register`, fill in username and password, submit, verify redirect to `/` with authenticated nav bar visible

### Implementation for User Story 1

- [x] T010 [US1] Create PlayerRegistrationLive at `lib/agenticrealms_web/live/player_registration_live.ex`: render registration form with username, password, and password confirmation fields using `Accounts.change_player_registration/2` changeset; validate on change (show inline errors for format, length, uniqueness); on submit call `Accounts.register_player/1`, then redirect through session controller to log in the player; include link to login page ("Already have an account? Log in"); style form to match terminal-revival design language

**Checkpoint**: Registration flow works end-to-end — new visitors can create accounts and are logged in automatically

---

## Phase 5: User Story 2 - Player Logs In and Navigates (Priority: P1)

**Goal**: Existing players can log in with credentials and navigate between home and game screen using the authenticated nav bar

**Independent Test**: Log in with valid credentials; verify nav bar appears with home icon, "Play" link, and username dropdown; click "Play" to reach game screen; click home icon to return; log out via dropdown

### Implementation for User Story 2

- [x] T011 [US2] Create PlayerLoginLive at `lib/agenticrealms_web/live/player_login_live.ex`: render login form with username and password fields; form action posts to `/login` (PlayerSessionController handles session); display generic error flash "Invalid username or password" on failure; include link to registration ("Don't have an account? Create one"); style form to match terminal-revival design language
- [x] T012 [US2] Update GameLive at `lib/agenticrealms_web/live/game_live.ex` and `lib/agenticrealms_web/live/game_live.html.heex`: remove `<.topbar>` component call; add inline Player/Wizard mode switch at the top of the game content area (below the nav bar rendered by layout); ensure GameLive uses `app` layout so the authenticated nav bar appears; verify all existing game functionality is preserved
- [x] T013 [US2] Remove or deprecate the `topbar/1` function component from `lib/agenticrealms_web/components/game_components.ex` since the nav bar is now in the layout and the mode switch is inline in GameLive

**Checkpoint**: Full login/navigation flow works — players can log in, see the nav bar on all pages, navigate to the game screen via "Play", return home, and log out

---

## Phase 6: User Story 4 - Player Modifies Their Profile (Priority: P2)

**Goal**: Authenticated players can change their username or password from a settings page

**Independent Test**: Navigate to settings via username dropdown, change username, verify it updates; change password, log out, log back in with new password

### Implementation for User Story 4

- [x] T014 [US4] Create PlayerSettingsLive at `lib/agenticrealms_web/live/player_settings_live.ex`: render two forms — username change form (shows current username, validates on change for format/length/uniqueness, saves on submit with success confirmation) and password change form (current password, new password, confirm new password, validates on change, saves on submit with success confirmation); style to match terminal-revival design language; use `app` layout for authenticated nav bar

**Checkpoint**: Players can update their profile — username and password changes work with proper validation and feedback

---

## Phase 7: User Story 5 - Player Deletes Their Account (Priority: P3)

**Goal**: Authenticated players can permanently delete their account with a two-step confirmation

**Independent Test**: Navigate to settings, click "Delete Account", verify confirmation modal appears, type username, confirm deletion, verify redirect to landing page and login with old credentials fails

### Implementation for User Story 5

- [x] T015 [US5] Add account deletion section to PlayerSettingsLive at `lib/agenticrealms_web/live/player_settings_live.ex`: add a "Danger Zone" section at the bottom of settings page; "Delete Account" button opens a confirmation modal warning that the action is permanent; modal requires typing username to confirm (delete button disabled until match); on confirm call `Accounts.delete_player/1`, clear session via redirect through session controller delete action, redirect to `/`; style danger zone with destructive visual treatment matching terminal-revival design language

**Checkpoint**: Account deletion works with two-step confirmation — deleted accounts cannot log in

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and cleanup across all stories

- [x] T016 [P] Verify unauthenticated access to `/play` and `/settings` redirects to `/login` with appropriate messaging
- [x] T017 [P] Verify authenticated access to `/login` and `/register` redirects to `/`
- [x] T018 [P] Verify session expiry edge case: when session is invalid, next navigation redirects to login
- [x] T019 Run `mix precommit` (format, compile warnings, test suite) and fix any issues
- [x] T020 Run quickstart.md validation: walk through all verification steps end-to-end in browser

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion — BLOCKS all user stories
- **US3 Landing Page (Phase 3)**: Depends on Phase 2 (needs router, layout)
- **US1 Registration (Phase 4)**: Depends on Phase 2 (needs Accounts context, auth plugs, router)
- **US2 Login & Navigation (Phase 5)**: Depends on Phase 2 (needs session controller, auth plugs, router)
- **US4 Profile Modification (Phase 6)**: Depends on Phase 2 (needs Accounts context, auth plugs)
- **US5 Account Deletion (Phase 7)**: Depends on Phase 6 (extends PlayerSettingsLive created in T014)
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **US3 (P1)**: Can start after Phase 2 — no dependencies on other stories
- **US1 (P1)**: Can start after Phase 2 — no dependencies on other stories
- **US2 (P1)**: Can start after Phase 2 — no dependencies on other stories
- **US4 (P2)**: Can start after Phase 2 — no dependencies on other stories
- **US5 (P3)**: Depends on US4 (extends the PlayerSettingsLive created in T014)

### Within Each User Story

- Schema/model before context (Phase 1 before Phase 2)
- Context before LiveViews
- Implementation before integration verification

### Parallel Opportunities

- **After Phase 2 completes**: US3 (T009), US1 (T010), and US2 (T011-T013) can all start in parallel
- **After Phase 2 completes**: US4 (T014) can also run in parallel with P1 stories
- **Within US2**: T012 and T013 modify different files and can run in parallel
- **Phase 8**: T016, T017, T018 can all run in parallel

---

## Parallel Example: After Foundational Phase

```
# All P1 stories can launch in parallel after Phase 2:
Task T009: "Create LandingLive at lib/agenticrealms_web/live/landing_live.ex"
Task T010: "Create PlayerRegistrationLive at lib/agenticrealms_web/live/player_registration_live.ex"
Task T011: "Create PlayerLoginLive at lib/agenticrealms_web/live/player_login_live.ex"

# Within US2, these can also run in parallel:
Task T012: "Update GameLive (remove topbar, add inline mode switch)"
Task T013: "Remove topbar/1 from game_components.ex"
```

---

## Implementation Strategy

### MVP First (US3 + US1 + US2)

1. Complete Phase 1: Setup (dependency, schema, migration)
2. Complete Phase 2: Foundational (context, auth plugs, router, nav bar)
3. Complete Phase 3: US3 — Landing page
4. Complete Phase 4: US1 — Registration
5. Complete Phase 5: US2 — Login & Navigation
6. **STOP and VALIDATE**: All P1 stories independently testable; full auth flow works

### Incremental Delivery

1. Setup + Foundational → Auth infrastructure ready
2. Add US3 (Landing) → Public entry point works
3. Add US1 (Registration) → New players can create accounts
4. Add US2 (Login & Navigation) → Full auth loop complete (MVP!)
5. Add US4 (Profile) → Players can manage their identity
6. Add US5 (Account Deletion) → Players can leave

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- The spec does not request TDD — test tasks are not included as separate items
- Login form uses POST to controller (not LiveView event) per Phoenix session conventions
- US5 extends the PlayerSettingsLive created in US4, so it depends on US4
- The existing game_live_test.exs tests should continue to pass after modifications in T012
