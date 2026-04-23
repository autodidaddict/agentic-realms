# Feature Specification: Player Authentication & Account Management

**Feature Branch**: `002-user-auth`  
**Created**: 2026-04-23  
**Status**: Draft  
**Input**: User description: "User auth - The application must support standard user features. Users can create a new player account, they can modify their own profile, and they can choose to delete their account (which requires extra confirmation). The user accounts are called Players. Every player will create an account with a username and a password. They do not need to supply any more information than that. The default landing (home) page should contain a hero image and a description of the agentic realms game. This and the login page are the only pages that can be accessed without an authenticated user. A new top navigation bar for those who are logged in includes a new menu item 'Play' which takes the player to the current game screen that was specified and implemented in the 001 spec. There is also a home icon on the top left of the new nav bar that takes a user to the home landing page."

## Clarifications

### Session 2026-04-23

- Q: How does a player access profile settings and log out from the navigation bar? → A: Username dropdown menu in the top-right corner containing "Settings" and "Log Out" items.
- Q: How does the new authenticated nav bar relate to the existing 001 game screen topbar? → A: New nav bar replaces the 001 topbar entirely; the Player/Wizard mode switch moves into the game screen content area (below the nav bar).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Player Creates a New Account (Priority: P1)

A new visitor arrives at the application and wants to start playing. They navigate to a registration page, enter a username and password, confirm their password, and submit the form. Upon successful registration, they are automatically logged in and redirected to the home landing page with the authenticated navigation bar visible.

**Why this priority**: Account creation is the entry point for all new players. Without it, no one can access any authenticated features. This is the foundational user journey that enables everything else.

**Independent Test**: Can be fully tested by navigating to the registration page, filling in a username and password, submitting, and verifying the player is logged in and sees the authenticated navigation bar.

**Acceptance Scenarios**:

1. **Given** an unauthenticated visitor is on the landing page, **When** they click a "Create Account" or "Sign Up" link, **Then** they are taken to a registration form with fields for username, password, and password confirmation.
2. **Given** a visitor is on the registration form, **When** they submit a valid username (unique, non-empty) and matching passwords (meeting minimum length), **Then** their account is created, they are automatically logged in, and they are redirected to the home landing page with the authenticated navigation bar.
3. **Given** a visitor is on the registration form, **When** they submit a username that already exists, **Then** they see an error message indicating the username is taken and the form is not submitted.
4. **Given** a visitor is on the registration form, **When** the passwords do not match or do not meet minimum length, **Then** they see an appropriate error message and the form is not submitted.

---

### User Story 2 - Player Logs In and Navigates (Priority: P1)

An existing player visits the application and logs in with their username and password. After logging in, they see an authenticated navigation bar with a home icon on the left and a "Play" menu item. They can navigate to the home landing page or the game screen.

**Why this priority**: Login is the gateway to all authenticated features. The navigation bar establishes the primary information architecture for authenticated users and connects the new auth system to the existing game screen from the 001 spec.

**Independent Test**: Can be fully tested by logging in with valid credentials, verifying the authenticated navigation bar appears, clicking "Play" to reach the game screen, and clicking the home icon to return to the landing page.

**Acceptance Scenarios**:

1. **Given** an unauthenticated visitor is on the landing page, **When** they click a "Log In" link, **Then** they are taken to a login form with username and password fields.
2. **Given** a player is on the login form, **When** they submit valid credentials, **Then** they are logged in and redirected to the home landing page with the authenticated navigation bar visible.
3. **Given** a player is on the login form, **When** they submit invalid credentials, **Then** they see a generic error message (e.g., "Invalid username or password") and remain on the login page.
4. **Given** an authenticated player sees the navigation bar, **When** they click the home icon on the top left, **Then** they are taken to the home landing page.
5. **Given** an authenticated player sees the navigation bar, **When** they click the "Play" menu item, **Then** they are taken to the game screen where the Player/Wizard mode switch appears in the content area (below the nav bar) rather than in the old 001 topbar, which is replaced by the new nav bar.
6. **Given** an authenticated player sees the navigation bar, **When** they click their username in the top-right corner, **Then** a dropdown menu appears with "Settings" and "Log Out" items.
7. **Given** an authenticated player has the username dropdown open, **When** they click "Log Out", **Then** their session ends and they are redirected to the home landing page as an unauthenticated visitor.

---

### User Story 3 - Visitor Views Landing Page (Priority: P1)

Any visitor (authenticated or not) can view the home landing page. The page features a hero image showcasing Agentic Realms and a description of the game. Unauthenticated visitors see links to log in or create an account. Authenticated players see the full navigation bar.

**Why this priority**: The landing page is the first impression of the application and the only content page accessible without authentication. It serves as both a marketing page and the authenticated user's home base.

**Independent Test**: Can be fully tested by loading the landing page without logging in and verifying the hero image, game description, and login/signup links are visible. Then log in and verify the navigation bar replaces the unauthenticated links.

**Acceptance Scenarios**:

1. **Given** an unauthenticated visitor navigates to the root URL, **When** the landing page loads, **Then** they see a hero image, a description of the Agentic Realms game, and links/buttons to "Log In" and "Create Account".
2. **Given** an authenticated player navigates to the root URL, **When** the landing page loads, **Then** they see the same hero image and game description, but with the authenticated navigation bar (home icon, "Play" menu item) instead of login/signup links.
3. **Given** an unauthenticated visitor, **When** they attempt to access any page other than the landing page, login page, or registration page, **Then** they are redirected to the login page.

---

### User Story 4 - Player Modifies Their Profile (Priority: P2)

An authenticated player navigates to their profile settings and can update their username or change their password. Changes take effect immediately upon successful submission.

**Why this priority**: Profile management is important for player identity but is not required to access the core gameplay. Players need to be able to play before they need to customize their profile.

**Independent Test**: Can be tested by navigating to profile settings, changing the username, saving, and verifying the updated username appears. Then change the password, log out, and log back in with the new password.

**Acceptance Scenarios**:

1. **Given** an authenticated player, **When** they click their username in the top-right corner and select "Settings" from the dropdown, **Then** they are taken to the profile settings page where they see their current username and options to change their username or password.
2. **Given** a player is on the profile settings page, **When** they change their username to a valid, unique value and save, **Then** the username is updated and they see a success confirmation.
3. **Given** a player is on the profile settings page, **When** they change their username to one that already exists, **Then** they see an error message and the username is not changed.
4. **Given** a player is on the profile settings page, **When** they change their password (providing current password and new password with confirmation), **Then** the password is updated and they see a success confirmation.
5. **Given** a player is on the profile settings page, **When** they provide an incorrect current password, **Then** the password change is rejected with an error message.

---

### User Story 5 - Player Deletes Their Account (Priority: P3)

An authenticated player decides to delete their account. They navigate to their profile settings and initiate account deletion. The system requires extra confirmation before permanently removing the account.

**Why this priority**: Account deletion is a destructive, infrequent action. It is important for user autonomy and data rights but is the least commonly used feature.

**Independent Test**: Can be tested by navigating to profile settings, clicking delete account, verifying a confirmation dialog appears, confirming deletion, and verifying the player is logged out and the account no longer exists.

**Acceptance Scenarios**:

1. **Given** an authenticated player is on their profile settings page, **When** they click "Delete Account", **Then** a confirmation dialog appears warning that this action is permanent and cannot be undone.
2. **Given** the deletion confirmation dialog is shown, **When** the player types their username to confirm and clicks the final "Delete" button, **Then** their account is permanently removed, their session ends, and they are redirected to the landing page as an unauthenticated visitor.
3. **Given** the deletion confirmation dialog is shown, **When** the player cancels or dismisses the dialog, **Then** no action is taken and they remain on the profile settings page.
4. **Given** a player's account has been deleted, **When** they attempt to log in with the old credentials, **Then** they see the generic "Invalid username or password" error.

---

### Edge Cases

- What happens when a player's session expires? They are redirected to the login page on their next navigation action, with a message indicating their session has expired.
- What happens when a player tries to register with a username that contains special characters? Usernames are validated to allow only alphanumeric characters, hyphens, and underscores (3-30 characters).
- What happens when a player navigates directly to the game screen URL without authentication? They are redirected to the login page.
- What happens when a player submits a password shorter than the minimum length? They see a validation error indicating the minimum password requirement (8 characters).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow visitors to create a new player account with a username and password.
- **FR-002**: System MUST validate that usernames are unique, contain only alphanumeric characters, hyphens, and underscores, and are between 3 and 30 characters long.
- **FR-003**: System MUST validate that passwords meet a minimum length of 8 characters.
- **FR-004**: System MUST securely hash passwords before storage — plaintext passwords are never stored.
- **FR-005**: System MUST allow players to log in with their username and password.
- **FR-006**: System MUST display a generic error message on failed login attempts that does not reveal whether the username or password was incorrect.
- **FR-007**: System MUST automatically log in a player after successful account creation.
- **FR-008**: System MUST allow authenticated players to log out, ending their session.
- **FR-009**: System MUST allow authenticated players to change their username, subject to the same uniqueness and format validations as registration.
- **FR-010**: System MUST allow authenticated players to change their password by providing their current password and a new password with confirmation.
- **FR-011**: System MUST allow authenticated players to delete their account with a two-step confirmation: first a warning dialog, then requiring the player to type their username to confirm.
- **FR-012**: System MUST permanently remove all player data upon account deletion.
- **FR-013**: System MUST display a home landing page with a hero image and game description that is accessible to all visitors (authenticated and unauthenticated).
- **FR-014**: System MUST display a login page accessible to unauthenticated visitors.
- **FR-015**: System MUST restrict access to all pages except the landing page, login page, and registration page to authenticated players only.
- **FR-016**: System MUST redirect unauthenticated visitors who attempt to access restricted pages to the login page.
- **FR-017**: System MUST display an authenticated navigation bar for logged-in players containing a home icon (top left, links to landing page), a "Play" menu item (links to the game screen from the 001 spec), and a username dropdown menu (top right) with "Settings" and "Log Out" items.
- **FR-018**: System MUST display unauthenticated navigation or links (Log In, Create Account) for visitors who are not logged in.
- **FR-019**: System MUST redirect players to the home landing page after successful login or registration.
- **FR-020**: System MUST replace the existing 001 game screen topbar with the new authenticated navigation bar; the Player/Wizard mode switch MUST be relocated into the game screen content area (below the nav bar).

### Key Entities

- **Player**: A registered user account. Key attributes: unique username, hashed password, creation timestamp. Players are the sole user type in the system.
- **Session**: An authenticated player's active session. Tracks which player is currently logged in and is invalidated on logout or account deletion.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: New players can complete account registration (username + password) in under 1 minute.
- **SC-002**: Returning players can log in within 15 seconds of reaching the login page.
- **SC-003**: 100% of unauthenticated requests to restricted pages result in a redirect to the login page — no protected content is leaked.
- **SC-004**: Players can update their username or password from the profile settings page and see the change reflected immediately.
- **SC-005**: Account deletion requires two explicit confirmation steps before the account is removed, preventing accidental deletion.
- **SC-006**: The home landing page loads with a visible hero image and game description for both authenticated and unauthenticated visitors.
- **SC-007**: The authenticated navigation bar displays on every page for logged-in players, with working links to the home page and game screen.
- **SC-008**: After account deletion, the player's credentials no longer grant access to the system.

## Assumptions

- The existing game screen from the 001 spec (Player/Wizard views) will be placed behind the authentication gate and accessible via the "Play" navigation item.
- Standard session-based authentication is used. No external identity providers (OAuth, SSO) are required.
- Password hashing follows industry-standard practices (e.g., bcrypt or similar) — the specific algorithm is an implementation detail.
- No email address is required for account creation; account recovery (e.g., "forgot password") is out of scope for this feature.
- No role-based access control beyond "authenticated" vs. "unauthenticated" is required.
- The hero image for the landing page will be a static asset provided as part of the implementation. The specific image content is an implementation detail.
- Mobile/responsive layouts are out of scope, consistent with the 001 spec.
- Rate limiting on login/registration attempts is an implementation detail and not specified here.
