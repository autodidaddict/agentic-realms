# Feature Specification: Real Stats — Players & NPCs

**Feature Branch**: `019-real-stats`  
**Created**: 2026-07-12  
**Status**: Draft  
**Input**: User description: "Real stats - Players and NPCs need to have real stats. Each player and NPC will get: strength, dex, constitution, intelligence, charisma, and wisdom each with the standard abbreviations STR DEX CON INT WIS CHA. Players and NPCs also get a level value. Players and only players get an XP (experience points) value. There is a level curve that determines level from XP, but level isn't derived all the time, only when XP is awarded. This gives NPCs the ability to have levels without requiring content creators to manually manage XP. All NPC stats are cloned from the blueprint. Players and NPCs both get current hitpoints (HP) and maximum hitpoints. Maximum hitpoints are copied from blueprints. When players are created the default maximum and current HP is 10. Str/dex/con/int/wis/cha all default to 12. Level always defaults to 1 and XP defaults to 0. Quests carry an XP reward that accompanies any other rewards like objects that are awarded upon completion. Anytime XP is awarded to a player (XP cannot be awarded to NPCs), the XP value is compared against the level curve and the player levels up if the curve indicates a higher level. The player's character sheet view needs to display all of the ability stats as well as XP, level, and current/max HP. A progress bar type affordance should be used to indicate how far until the next level. When examining an NPC or player, a sentence should be used to describe the % of max HP using tiers like Very healthy, Healthy, Weakened, Very Weakened, At death's door. Examining a player or an NPC should never reveal the numbers for any ability scores, level, or XP. Examining an NPC or Player will also include a phrase describing the target's relative level and not specific, e.g. Much weaker, weaker, about as powerful, more powerful, too powerful to even compare. When this is done there should be no faked or mock stats on the player's information screen, which means removing any old UI elements that don't carry one of the stats specified in this feature. A notification in the chat window should notify a player when they gain XP or when they level up."

## Clarifications

### Session 2026-07-12

- Q: When a player levels up in this milestone, should any stats increase automatically, or does leveling only change the level value? → A: Only the level value changes — no automatic stat growth (max HP/mana and ability scores unchanged); stat growth is deferred to the combat milestone.
- Q: What shape should the level curve take, and is there a level cap? → A: A compounding quadratic `XP(L) = a·L² + b·L + c` (D&D-style), with coefficients a=50, b=−50, c=0 giving thresholds 0/100/300/600/1000/1500…; unbounded (no level cap).
- Q: Should existing seeded quests carry a real experience reward so the level-up loop is demonstrable from seed data? → A: Yes — the existing starter/fetch quest awards 100 experience (enough to reach Level 2); other seeded quests default to 0 unless authored.
- Q: Keep the documented qualitative bands, or adjust? → A: Keep health tiers as documented; tighten the relative-power spread so extremes trigger at ±4 (Much weaker ≤ −4; weaker −3…−2; about as powerful −1…+1; more powerful +2…+3; too powerful to even compare ≥ +4).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A real character sheet (Priority: P1)

A player opens their character sheet and sees their **actual** character: their real name, their level, their experience toward the next level shown as a progress affordance, their current and maximum hitpoints, their current and maximum mana, and their six ability scores (STR, DEX, CON, INT, WIS, CHA). Every value shown is the player's own persisted data — there are no invented or placeholder stats anywhere on the information screen.

**Why this priority**: The character information screen currently shows hardcoded, identical-for-everyone placeholder values (a fake name, class, hitpoints, mana, and experience). Replacing that with real, per-player data is the foundational payoff of the whole feature and is independently valuable even before anything changes those values. It is also the prerequisite surface for Stories 2 and 3.

**Independent Test**: Create a brand-new player and open the character sheet. Confirm it shows the player's real name, Level 1, 0 experience, 10/10 hitpoints, 10/10 mana, and all six ability scores at 12 — and that no placeholder element (fabricated class/deity, fabricated name, or any other value not defined by this feature) appears anywhere on the screen.

**Acceptance Scenarios**:

1. **Given** a newly created player, **When** they open the character sheet, **Then** it shows their real name, Level 1, 0 experience with an empty-to-start progress affordance toward Level 2, 10/10 hitpoints, 10/10 mana, and STR/DEX/CON/INT/WIS/CHA all equal to 12.
2. **Given** a player whose stats have changed during play, **When** they view the character sheet, **Then** every displayed value matches their current persisted stats.
3. **Given** the character sheet is displayed, **When** it is inspected for content, **Then** it contains no value that is not one of: name, level, experience/progress, current/max hitpoints, current/max mana, or one of the six ability scores.
4. **Given** a player logs out and logs back in, **When** they reopen the character sheet, **Then** all stat values are exactly as they were before logout.

---

### User Story 2 - Earn experience and level up from quests (Priority: P2)

When a player completes a quest, they receive the quest's experience reward alongside any item rewards. Their experience total increases, their level rises if the new total crosses one or more thresholds on the level curve, and they are notified in the chat/log window that they gained experience and — if applicable — that they reached a new level. The character sheet's level and progress affordance reflect the change.

**Why this priority**: This is the first live loop that makes stats *move* — the reason the numbers on the sheet feel earned rather than static. It depends on Story 1's sheet existing but is separately demonstrable.

**Independent Test**: Complete a quest whose experience reward is large enough to cross a level boundary. Confirm the experience total increased by exactly the reward, the level increased to the value the curve indicates, an experience-gain message and a level-up message appeared in the chat window, and the character sheet's level and progress affordance updated.

**Acceptance Scenarios**:

1. **Given** a Level 1 player with 0 experience and a completable quest that rewards enough experience to reach Level 2, **When** the player completes the quest, **Then** their experience total increases by the reward, their level becomes 2, and the chat window shows both an experience-gain notice and a level-up notice.
2. **Given** a player completes a quest whose experience reward is not enough to cross the next threshold, **When** the reward is granted, **Then** their experience total increases, their level is unchanged, and only an experience-gain notice is shown (no level-up notice).
3. **Given** a quest reward large enough to cross multiple thresholds at once, **When** it is granted, **Then** the player's level advances to the highest level the curve allows for the new total, and the level-up notice reflects that final level.
4. **Given** an NPC, **When** any experience-awarding path is attempted against it, **Then** no experience is recorded (NPCs never hold experience).
5. **Given** a quest with no experience reward (reward of 0), **When** it is completed, **Then** the experience total is unchanged and no experience-gain notice is shown.

---

### User Story 3 - Size up a target by examining it (Priority: P3)

When a player examines another player or an NPC, the description now includes a sentence conveying the target's health as a qualitative tier (a band of its percentage of maximum hitpoints) and a phrase conveying how powerful the target is relative to the examiner (a band of their level difference). Exact numbers for ability scores, level, and experience are never revealed.

**Why this priority**: This gives NPC stats (and other players' stats) a player-facing surface without requiring combat, and adds tactical texture to the world. It builds on the existing examine capability and on Stories 1–2 having established real stats.

**Independent Test**: Examine several NPCs spanning a range of levels relative to the examiner and a range of current-health percentages. Confirm the health sentence matches the correct tier, the relative-power phrase matches the correct band, and no exact ability score, level, or experience number appears in the output.

**Acceptance Scenarios**:

1. **Given** an NPC at full health and roughly the examiner's level, **When** the player examines it, **Then** the output includes a "Very healthy" (or equivalent top-tier) health sentence and an "about as powerful" relative-power phrase.
2. **Given** an NPC that is far higher level than the examiner, **When** the player examines it, **Then** the relative-power phrase is the top band (e.g., "too powerful to even compare").
3. **Given** an NPC at a low fraction of its maximum hitpoints, **When** the player examines it, **Then** the health sentence uses the appropriate low tier (e.g., "Very Weakened" or "At death's door").
4. **Given** any examine of a player or NPC, **When** the output is inspected, **Then** it contains no exact number for any ability score, level, or experience value.
5. **Given** another player as the target, **When** examined, **Then** the same health-tier sentence and relative-power phrase are produced, computed from that player's real stats.

---

### Edge Cases

- **Multi-level jump**: An experience award that crosses more than one threshold advances the player to the highest level the curve permits for the new total; the level-up notice names the final level (not each intermediate one).
- **Unbounded curve**: The level curve has no cap; there is always a defined next-level threshold, so the progress affordance always shows progress toward a real next level (there is no special maximum-level state).
- **Zero-reward quest**: Completing a quest whose experience reward is 0 changes nothing about experience or level and produces no experience notice.
- **Exactly zero hitpoints**: A target at 0 current hitpoints reports the lowest health tier ("At death's door"); death, removal, and respawn are out of scope for this milestone, so a 0-HP entity simply reports that tier.
- **Examining yourself**: Self-examination behaves as it does today and does not include a relative-power comparison to yourself (a self comparison is meaningless).
- **Independent clones**: Two NPCs cloned from the same blueprint carry independent current-hitpoint values; one being at a different health tier than the other is expected.
- **NPC level source**: An NPC's level comes directly from its cloned stats and is never recomputed from experience (NPCs have no experience).

## Requirements *(mandatory)*

### Functional Requirements

**Stats every entity carries**

- **FR-001**: Every player and every NPC MUST have six ability scores identified as STR (strength), DEX (dexterity), CON (constitution), INT (intelligence), WIS (wisdom), and CHA (charisma).
- **FR-002**: Every player and every NPC MUST have a level value, both a current-hitpoints and a maximum-hitpoints value, and both a current-mana and a maximum-mana value.
- **FR-003**: Players — and only players — MUST have an experience (XP) value. NPCs MUST NOT have an experience value.
- **FR-004**: In this milestone, ability scores are established and displayed but MUST NOT influence any game outcome (they are data for future milestones such as combat).

**Defaults & initialization**

- **FR-005**: A newly created player MUST start with each ability score = 12, level = 1, experience = 0, maximum hitpoints = 10, current hitpoints = 10, maximum mana = 10, and current mana = 10.
- **FR-006**: An NPC's ability scores, level, maximum hitpoints, and maximum mana MUST be copied from its blueprint at spawn (a frozen per-instance copy), and its current hitpoints and current mana MUST be initialized to their maxima at spawn.
- **FR-007**: Each NPC instance's current hitpoints and current mana MUST be independent of its blueprint and of every other instance cloned from the same blueprint.

**Level curve & experience**

- **FR-008**: The system MUST define a level curve that maps a cumulative experience total to a level, derived from a compounding quadratic `XP(L) = a·L² + b·L + c` (with `XP(1) = 0`); it MUST be monotonic non-decreasing (more experience never yields a lower level) and unbounded (every level has a defined next-level threshold — there is no level cap).
- **FR-009**: A player's stored level MUST be re-evaluated against the curve only at the moment experience is awarded, and MUST remain stable between awards (it is not recomputed on every read).
- **FR-010**: An NPC's level MUST be set directly from its cloned stats and MUST NOT be derived from experience, so content creators can assign NPC levels without managing experience.
- **FR-011**: When experience is awarded to a player, the system MUST add the awarded amount to the player's experience total and re-evaluate the player's level against the curve; if the curve indicates a higher level for the new total, the player's level MUST increase accordingly (possibly by more than one level).
- **FR-011a**: Leveling up in this milestone MUST change only the player's level value; it MUST NOT alter maximum hitpoints, maximum mana, ability scores, or any other stat (stat growth is deferred to a later milestone).
- **FR-012**: Awarding experience MUST apply to players only; the system MUST provide no path to give an NPC experience.
- **FR-013**: Quests MUST carry an experience reward that is granted upon completion, in addition to any item or other rewards, and MUST support a reward of 0.

**Character sheet**

- **FR-014**: The character sheet MUST display the player's real name, current level, current experience with a progress affordance indicating how far the player has advanced toward the next level, current and maximum hitpoints, current and maximum mana, and all six ability scores with their values.
- **FR-015**: The progress affordance MUST reflect the fraction of the way from the current level's threshold to the next level's threshold for the player's current experience total. Because the curve is unbounded, every level has a defined next-level threshold and the affordance is always well-defined.
- **FR-016**: The character sheet MUST NOT display any value that is not one of the stats defined by this feature; every prior placeholder or mock element on the information screen that is not backed by such a stat (including the fabricated class/deity and the placeholder name) MUST be removed. Mana is a stat defined by this feature and MUST be displayed with the player's real current/maximum values rather than removed.
- **FR-017**: The character sheet MUST reflect the player's current stats, updating to show experience, level, hitpoint, and mana changes without requiring the player to close and reopen it.

**Examining players & NPCs**

- **FR-018**: Examining a player or an NPC MUST include a sentence describing the target's health as a qualitative tier derived from its current hitpoints as a percentage of its maximum hitpoints, using the tiers: Very healthy, Healthy, Weakened, Very Weakened, At death's door.
- **FR-019**: Examining a player or an NPC MUST include a phrase describing the target's power relative to the examiner, derived from the difference between their levels, using bands such as: Much weaker, weaker, about as powerful, more powerful, too powerful to even compare.
- **FR-020**: Examine output MUST NOT reveal any exact numeric value for an ability score, a level, an experience total, or mana for the examined target; current hitpoints are conveyed only as the qualitative health tier of FR-018, and mana is not surfaced by examine at all.
- **FR-021**: The relative-power phrase MUST be computed against the examiner's own level; self-examination MUST NOT include a relative-power phrase.

**Notifications**

- **FR-022**: When a player gains experience, the system MUST notify that player in the chat/log window of the experience gained.
- **FR-023**: When a player's level increases, the system MUST notify that player in the chat/log window of the new level.

**Persistence**

- **FR-024**: A player's stats (ability scores, level, experience, current and maximum hitpoints) MUST persist across sessions, unchanged by logging out and back in.

### Key Entities *(include if feature involves data)*

- **Player stats**: The six ability scores, level, experience, current/maximum hitpoints, and current/maximum mana belonging to a specific player; persisted and authoritative for that player.
- **NPC stats**: The six ability scores, level, current/maximum hitpoints, and current/maximum mana belonging to a specific NPC instance; a frozen copy made from the NPC's blueprint at spawn, with current hitpoints and current mana tracked per instance.
- **NPC blueprint base stats**: The authored ability scores, level, maximum hitpoints, and maximum mana on an NPC blueprint that seed each clone's stats at spawn.
- **Level curve**: The mapping from a cumulative experience total to a level; also yields the per-level thresholds used to render the character sheet's progress affordance.
- **Quest experience reward**: An experience value attached to a quest that is granted to the completing player alongside other rewards.
- **Health tier**: A qualitative band of current hitpoints as a percentage of maximum hitpoints, used in examine output.
- **Relative-power band**: A qualitative band of the level difference between an examined target and the examiner, used in examine output.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A newly created player's character sheet shows their real name, Level 1, 0 experience, 10/10 hitpoints, 10/10 mana, and all six ability scores at 12.
- **SC-002**: 100% of the values shown on the character-information screen correspond to the viewing player's actual persisted stats; zero placeholder or hardcoded stat values remain anywhere on that screen.
- **SC-003**: Completing a quest whose experience reward crosses at least one level threshold results, within the single completion interaction, in the player's experience total increasing by exactly the reward, the level advancing to the curve-indicated value, and both an experience-gain notice and a level-up notice appearing in the chat window.
- **SC-004**: Completing a quest whose reward does not cross a threshold increases experience and shows an experience-gain notice with no level-up notice, in 100% of such cases.
- **SC-005**: Examining any player or NPC produces exactly one health-tier sentence and exactly one relative-power phrase, and reveals no exact ability-score, level, or experience number, in 100% of examinations.
- **SC-006**: Across targets spanning every health tier and every relative-power band, the tier and band shown match the target's actual current-hitpoint percentage and level difference in 100% of cases.
- **SC-007**: A player's stats are identical before and after a logout/login cycle in 100% of cases.
- **SC-008**: For any experience total, the character sheet's progress affordance reflects the correct fraction toward the next level (0% just after reaching a level, approaching 100% just before the next threshold).
- **SC-009**: No experience value is ever recorded for any NPC.

## Assumptions

- **Level curve (compounding quadratic)**: Cumulative experience required to *reach* level L follows a D&D-style compounding quadratic `XP(L) = a·L² + b·L + c` with the constraint `XP(1) = 0`. Concrete starting coefficients are `a = 50`, `b = −50`, `c = 0` (equivalently `50 × (L − 1) × L`), giving thresholds 0, 100, 300, 600, 1000, 1500, 2100, … — each level costs 100 more experience than the previous. Coefficients are tunable. The curve is unbounded (no level cap), so there is always a next-level threshold and the progress affordance is always well-defined.
- **Health tier bands (tunable default)**, by current HP as a percentage of max HP: Very healthy ≥ 90%; Healthy 65–89%; Weakened 35–64%; Very Weakened 10–34%; At death's door below 10% (including exactly 0).
- **Relative-power bands (tunable default)**, by (target level − examiner level): "Much weaker" when ≤ −4; "weaker" when −3 to −2; "about as powerful" when −1 to +1; "more powerful" when +2 to +3; "too powerful to even compare" when ≥ +4.
- **No stat growth on level-up in this milestone**: Leveling up changes the player's level value (and triggers the notice) only. Maximum hitpoints, ability scores, and other stats do NOT automatically increase on level-up; such growth is deferred to a later milestone.
- **Mana is a real stat; class is not**: Mana is a first-class stat for both players and NPCs, structured exactly like hitpoints (a current value and a maximum value), and is displayed on the character sheet with real values. The prior mock screen's class/deity line is not a stat defined by this feature and is removed rather than made real. Players default to 10 maximum and 10 current mana (mirroring the hitpoint default, since no other default was specified); an NPC's maximum mana comes from its blueprint (defaulting to 10 when unauthored). This mana default is a tunable placeholder.
- **Experience is monotonic**: Experience is non-negative and only ever increases in this milestone; there is no experience loss, level loss, or de-leveling.
- **Quest reward authoring**: Each quest defines its experience reward; quests seeded without an explicit reward default to 0 experience. The existing starter/fetch quest is authored with a **100-experience** reward (enough to reach Level 2) so the experience-gain and level-up loop is demonstrable directly from seed data.
- **NPC blueprint stat defaults**: NPC blueprints that do not author explicit stats default to the same starting values as players (ability scores 12, level 1, maximum hitpoints 10, maximum mana 10). Authoring NPC blueprint stats is seed-time in this milestone (no new wizard authoring UI), consistent with how NPC behaviors are authored today.
- **Reseed, not migrate**: Existing players, NPC blueprints, and NPC instances are re-seeded/re-initialized with default stats rather than data-migrated, consistent with the current pre-launch event-log policy.
- **Builds on existing capabilities**: Examining players/NPCs (feature 006), quest completion and rewards (feature 013), the NPC blueprint→clone model (features 008/015/016), and the chat/log notification surface all already exist; this feature extends them rather than introducing new interaction verbs.
- **No combat or spellcasting this milestone**: Nothing yet reduces hitpoints or mana in play; current hitpoints and current mana start at maximum and remain there until a future milestone introduces damage and spellcasting. The examine health tiers are fully exercised via authored/seeded NPC current-hitpoint values.
