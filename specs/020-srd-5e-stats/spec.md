# Feature Specification: SRD 5e Character Stats

**Feature Branch**: `020-srd-5e-stats`
**Created**: 2026-07-28
**Status**: Draft
**Input**: User description: "SRD 5e stats - Incorporate the new Elixir package srd_5e and use it and other SRD 5.2 assumptions regarding player and character stats. Player stats need to support the D&D style stats layout. The character sheet UI must have multiple tabs to support the standard model of interacting with a character sheet - main stats, abilities and modifiers, and spells. The spells UI tab is empty and left for later development. Character creation does not yet support players interactively defining their characters. The new player stats generation should just choose the human species and whatever other reasonable defaults are required."

Feature 019 gave every player six ability scores, a level, hitpoints and a mana pool. Those numbers are ours, not the SRD's: every score defaults to 12, hitpoints are a flat 10, and nothing derives from anything else. A player looking at the sheet sees six raw numbers and no way to tell what they mean.

This feature replaces that placeholder model with a real SRD 5.2 character. A character now has a species, a class, and a background; ability scores come from the SRD's standard array; and everything a player would expect to read off a character sheet is derived by the project's SRD rules library rather than invented here. Experience follows the SRD's own table, which moves into that library along with the rest of the rules. Mana goes away, since the SRD has no such resource and spell slots are the thing that eventually replaces it. The sheet itself becomes tabbed, matching how people actually read a character sheet.

Players still do not choose any of it. Character creation stays automatic this milestone, picking a human of a fixed default class and background. Interactive creation, spellcasting, and combat are later work.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read a real character sheet (Priority: P1)

A player opens the character sheet and finds the character described the way the tabletop game describes one. The first tab carries identity and vitals: name, species, class, background, level, experience progress, hitpoints, hit dice, armor class, initiative, speed, size, and proficiency bonus. The second tab carries the six ability scores with their modifiers, the six saving throws with proficiency marked, and every skill with its modifier and proficiency marked. The third tab is for spells and says so, but has nothing in it yet.

**Why this priority**: This is the whole visible payoff. A player cannot act on stats they cannot read, and every other slice of this feature exists to put correct numbers on this surface.

**Independent Test**: Log in, open the character sheet, and switch between all three tabs. Every value shown is derived from the character's own record, matches what the SRD rules produce for that character, and no value is a leftover placeholder.

**Acceptance Scenarios**:

1. **Given** a player with a character, **When** they open the character sheet, **Then** the main stats tab is selected by default and shows species, class, background, level, experience progress, current and maximum hitpoints, hit dice, armor class, initiative, speed, size, and proficiency bonus.
2. **Given** the character sheet is open, **When** the player selects the abilities tab, **Then** all six ability scores appear with their SRD modifiers formatted with an explicit sign, alongside all six saving throws and all eighteen skills with their modifiers and proficiency clearly marked.
3. **Given** the character sheet is open, **When** the player selects the spells tab, **Then** the tab renders an explicit placeholder stating spellcasting is not yet available, and the sheet does not error or appear broken.
4. **Given** the player has switched to a non-default tab, **When** they close and reopen the sheet, **Then** the sheet opens on the main stats tab again.
5. **Given** the character sheet is open, **When** the player presses Escape, **Then** the whole sheet closes regardless of which tab is selected.
6. **Given** a character with an ability score of 8, **When** the player views the abilities tab, **Then** the modifier reads `-1`, and a score of 15 reads `+2`.

---

### User Story 2 - Start as a complete, valid character (Priority: P2)

A new player entering the world is given a complete SRD character without being asked anything. They are a human of the default class and background, with ability scores taken from the SRD standard array and assigned to suit that class, and with hitpoints, armor class, proficiency bonus, saving throws, and skill proficiencies all derived from those choices. Nothing about creation is interactive.

**Why this priority**: Without this, the sheet in Story 1 has nothing correct to display. It is second only because the sheet is what the player sees, and a sheet fed by the existing placeholder values still demonstrates the tabs.

**Independent Test**: Create a new account, enter the world, and inspect the resulting character. It has a species, class, background, a full standard-array spread, and derived values that agree with the SRD rules for a level 1 character of that class. No prompt or form appeared at any point.

**Acceptance Scenarios**:

1. **Given** a brand new player, **When** their character is created, **Then** the character's species is Human and its class and background are the configured defaults, with no prompt shown.
2. **Given** a brand new character, **When** its ability scores are read, **Then** the six scores are exactly the SRD standard array, assigned so the class's primary ability holds the highest score.
3. **Given** a brand new character, **When** its maximum hitpoints are read, **Then** they equal the SRD level 1 result for that class's hit die plus its Constitution modifier, and current hitpoints equal maximum.
4. **Given** a brand new character, **When** its armor class is read, **Then** it equals the SRD unarmored value for its Dexterity modifier.
5. **Given** a brand new character, **When** its skill and saving throw proficiencies are read, **Then** they are the ones its class and background grant under the SRD.
6. **Given** two players created at different times with the same defaults, **When** their sheets are compared, **Then** their starting stats are identical, because generation is deterministic.

---

### User Story 3 - Derived values stay correct as the character grows (Priority: P3)

When a player gains enough experience to level up, every value that the SRD derives from level changes with it. Proficiency bonus rises on the SRD schedule, maximum hitpoints grow by the class's per-level amount, hit dice increase, and every saving throw and skill that benefits from proficiency shifts accordingly. If the sheet is open when this happens, it updates in place.

**Why this priority**: Leveling already exists from feature 019, so this is about keeping the new derived layer honest rather than adding a new player capability. It is real work, but the feature is still worth shipping without it if the first two slices land.

**Independent Test**: Award a character enough experience to cross a level threshold, then re-read the sheet. Proficiency bonus, maximum hitpoints, hit dice, saving throws, and skills all reflect the new level.

**Acceptance Scenarios**:

1. **Given** a level 4 character, **When** they reach level 5, **Then** their proficiency bonus changes from +2 to +3 and every proficient saving throw and skill modifier rises by 1.
2. **Given** a character levels up, **When** their maximum hitpoints are read, **Then** they have increased by the SRD per-level amount for their class plus their Constitution modifier, and current hitpoints have risen by the same amount.
3. **Given** the character sheet is open when the player levels up, **When** the level-up occurs, **Then** the visible values update without the player reopening the sheet.
4. **Given** a level 20 character, **When** they are awarded further experience, **Then** the experience is recorded, the level stays at 20, and the sheet presents the character as fully levelled rather than showing progress toward a level 21 that does not exist.

---

### Edge Cases

- A player whose character record predates this feature has no species, class, or background. The system must present them as a complete character rather than blanks or errors.
- The character sheet is opened in the instant between account creation and the character record being available. The sheet must render sensible defaults rather than crash or show empty fields.
- An ability score is low enough to produce a negative modifier, or a Constitution modifier is negative enough to reduce hitpoints. Hitpoints must never be presented as zero or below at creation.
- A character reaches level 20. Experience continues to accrue but level, proficiency bonus, and hit dice stop, and the experience bar has no next threshold to fill toward.
- A character's stored experience total sits between two thresholds under the new table where it previously implied a different level. The character's level must be recomputed from the table rather than trusted as stored.
- The spells tab is viewed by a character of a class that cannot cast. The placeholder must be the same either way, since spellcasting is out of scope.
- The sheet is viewed on a narrow window. The tab strip must remain usable and no tab may become unreachable.
- Examining another player or an NPC must continue to reveal only qualitative bands, never any of the new numbers.
- Two characters have the same defaults but different levels. Relative-power phrasing on examine must continue to work from level alone.

## Requirements *(mandatory)*

### Functional Requirements

#### Character model

- **FR-001**: A character MUST carry a species, a class, and a background, each identified by a stable SRD identifier.
- **FR-002**: A character MUST carry the six SRD ability scores (Strength, Dexterity, Constitution, Intelligence, Wisdom, Charisma) as integers.
- **FR-003**: A character MUST carry a level, an experience total, current and maximum hitpoints, and its hit dice.
- **FR-004**: A character MUST carry its set of skill proficiencies and its set of saving throw proficiencies.
- **FR-005**: The system MUST persist every stat listed in FR-001 through FR-004 so a character reads back identically across sessions and server restarts.
- **FR-006**: Every value the SRD defines as derived (ability modifiers, proficiency bonus, saving throw modifiers, skill modifiers, passive perception, armor class, initiative, speed, size, hit dice) MUST be computed from the persisted stats using the project's SRD rules library, not stored independently and not reimplemented in this project.
- **FR-007**: Ability modifiers MUST be presented with an explicit sign, so `+2` and `-1` are unambiguous.

#### Character creation

- **FR-008**: Character creation MUST NOT prompt the player for any choice. It runs to completion with no interactive step.
- **FR-009**: New characters MUST be created as the Human species.
- **FR-010**: New characters MUST be assigned the configured default class and default background, and changing those defaults MUST NOT require changing any code outside a single declared place.
- **FR-011**: New characters MUST receive the SRD standard array (15, 14, 13, 12, 10, 8) for their ability scores, assigned so the highest scores land on the class's primary and secondary abilities.
- **FR-012**: New characters MUST receive the skill and saving throw proficiencies their class and background grant under the SRD. Where the SRD offers a choice, the system MUST pick deterministically so two characters created with the same defaults are identical.
- **FR-013**: A new character's maximum hitpoints MUST equal the SRD level 1 value for its class hit die plus its Constitution modifier, floored at 1, and its current hitpoints MUST equal its maximum.
- **FR-014**: A character with no equipped armor MUST have the SRD unarmored armor class.

#### Character sheet

- **FR-015**: The character sheet MUST present three tabs: main stats, abilities and modifiers, and spells.
- **FR-016**: The main stats tab MUST be selected when the sheet opens, and MUST show name, species, class, background, level, experience progress toward the next level, current and maximum hitpoints, hit dice, armor class, initiative, speed, size, and proficiency bonus.
- **FR-017**: The abilities tab MUST show all six ability scores with their modifiers, all six saving throws with their modifiers and proficiency marked, and all eighteen SRD skills with their modifiers and proficiency marked.
- **FR-018**: The spells tab MUST render an explicit placeholder indicating spellcasting is not yet implemented, and MUST contain no spell data.
- **FR-019**: Switching tabs MUST NOT require a server round trip and MUST NOT close the sheet or lose the player's place in the game.
- **FR-020**: Tab selection MUST reset to the main stats tab each time the sheet is opened.
- **FR-021**: The existing close affordances (Escape, the close control, clicking outside) MUST continue to close the whole sheet from any tab.
- **FR-022**: The sheet MUST contain no placeholder or mock values. Every value shown MUST come from the viewing player's own character.
- **FR-023**: The sidebar summary card MUST continue to show the character's name, level, health, and experience progress, drawn from the same stats as the sheet.
- **FR-024**: When a character's stats change while the sheet is open, the displayed values MUST update without the player reopening it.

#### Existing behavior

- **FR-025**: Examining another player or an NPC MUST continue to reveal only qualitative health and relative-power phrasing, and MUST NOT reveal any ability score, modifier, armor class, exact hitpoint value, level, or experience total.
- **FR-026**: Awarding experience from quest completion MUST continue to work and MUST remain idempotent under repeated delivery.
- **FR-027**: Characters created before this feature MUST be presented as complete SRD characters, either by assigning them the same defaults a new character receives or by recreating the world's starting state. No character may render with missing species, class, or background.

#### Progression

- **FR-028**: Level progression MUST follow the SRD 5.2 experience table (level 2 at 300, level 3 at 900, through level 20 at 355,000), replacing the custom curve introduced in feature 019.
- **FR-029**: Level 20 MUST be the maximum. Experience awarded beyond the level 20 threshold MUST still be recorded, but MUST NOT raise the level or any value derived from it.
- **FR-030**: The experience table and the calculations over it (the level for an experience total, the threshold for a level, and progress toward the next level) MUST live in the shared SRD rules library alongside the other SRD rules, not in this project.
- **FR-031**: Existing experience rewards MUST be rescaled so progression stays meaningful against the new table.

#### Resources

- **FR-032**: The mana pool MUST be removed from the character model and from every player-facing surface, including the sidebar summary card and the character sheet. The character carries no magical resource this milestone.
- **FR-033**: No surface may show a mana value, a mana bar, or a mana caption after this feature ships.

#### NPCs

- **FR-034**: NPC stats MUST keep the shape feature 019 gave them. This feature changes no NPC blueprint, no spawn behavior, and no NPC record.
- **FR-035**: Examine MUST continue to work against NPCs unchanged, reading only the level and hitpoint values NPCs already carry.

### Key Entities

- **Character**: The playable identity behind a player account. Carries species, class, background, six ability scores, level, experience, hitpoints, hit dice, and its proficiency sets. Everything else about it is derived.
- **Species**: What the character is, drawn from the SRD catalog. Supplies size and speed. Fixed to Human this milestone.
- **Class**: What the character does, drawn from the SRD catalog. Supplies the hit die, saving throw proficiencies, the skills it may be proficient in, and its primary ability. Fixed to a single default this milestone.
- **Background**: Where the character came from, drawn from the SRD catalog. Supplies two skill proficiencies and the ability score increases the 2024 rules attach to it. Fixed to a single default this milestone.
- **Ability scores**: The six SRD scores. Every modifier, saving throw, and skill check derives from these plus the proficiency bonus.
- **Derived stats**: Ability modifiers, proficiency bonus, saving throws, skills, passive perception, armor class, initiative. Computed on read from the character and the SRD rules, never stored.
- **Character sheet**: The player-facing view of a Character, organized into three tabs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A player can find any of their character's stats within three interactions of opening the sheet: open, pick a tab, read.
- **SC-002**: 100% of the values on the character sheet trace to the viewing player's own character. Zero placeholder, mock, or hardcoded values remain on any stat surface.
- **SC-003**: Every derived value shown on the sheet matches, for the same inputs, what the SRD 5.2 rules produce. Verified by comparing at least one character at every proficiency-bonus band (levels 1, 5, 9, 13, 17, and 20) against the published SRD values.
- **SC-009**: All twenty SRD experience thresholds map to the correct level, including each exact threshold value and each value one short of it.
- **SC-004**: A new player goes from account creation to standing in the world with a complete, valid character with no prompt and no additional step beyond what exists today.
- **SC-005**: Switching between tabs is visually immediate, with no perceptible delay and no loss of game state.
- **SC-006**: After a level-up, an open character sheet shows the new level and every affected derived value within one second, without the player reopening it.
- **SC-007**: Examining another player or an NPC reveals zero exact numbers. Verified across every health band and every relative-power band.
- **SC-008**: Every character in the world, including ones created before this feature, renders a complete sheet with no blank or missing field.

## Assumptions

- The project's SRD 5.2 rules library, which already lives in this repository as a local package, is the single source of truth for SRD rules and content. It is consumed as a dependency rather than duplicated. Where a rule is not yet implemented there, this feature adds it to the library rather than working around it in the game. The experience table is the clearest case: the library does not carry one yet, so this feature puts it there.
- The custom experience curve feature 019 added to the game is superseded by the library's table and is removed rather than kept alongside it.
- Rescaling existing experience rewards means bringing the seeded quest rewards into proportion with the SRD table, so an early quest is worth a visible fraction of the 300 needed for level 2 rather than a third of it by accident. The exact values are a content decision for planning.
- Removing mana touches only the player character model and the player-facing surfaces. NPC records keep whatever mana values they already hold, since NPCs are untouched this milestone. Those values simply stop being read.
- The default class is Fighter and the default background is Soldier. Fighter needs no spellcasting, which is deferred, and both are in the SRD catalog. Both are configurable in one place so a later feature can change them without touching the character model.
- The 2024 SRD assigns ability score increases through the background rather than the species. Human grants no ability score increase, so the standard array is applied and then the background's increases are added.
- Human's Skillful and Versatile traits each ask the player to choose. Since creation is not interactive, the system picks a fixed, documented option for each. The choice is recorded on the character so a later interactive creation flow can change it.
- Subclasses arrive at level 3 in the SRD and are out of scope. A character above level 3 has no subclass this milestone, and the sheet does not show a subclass field.
- Feats beyond the background's origin feat are out of scope, as are ability score improvements at level 4 and above. Ability scores do not change after creation this milestone.
- Equipment does not affect armor class. Starting equipment is not granted, no armor or shield can be worn, and armor class is always the unarmored value. Equipment-driven armor class is later work alongside combat.
- Combat, damage, healing, death saves, rests, and conditions are out of scope even though the rules library supports them. Hitpoints change only through level-up this milestone.
- Multiclassing is out of scope.
- NPCs keep the stat block feature 019 gave them. Giving NPCs real SRD stat blocks is its own feature, and it will want blueprint, authoring, and seed changes this one deliberately avoids.
- The world's event log is destroyable at this stage, so existing state may be recreated rather than migrated where that is simpler.
- Which tab is selected is a purely local concern and is not persisted between sessions.
- The character sheet keeps its existing entry point, styling, and close behavior. This feature changes what is inside it, not how it is reached.

## Out of Scope

- Interactive character creation. Players cannot choose species, class, background, ability scores, skills, or feats.
- Spellcasting of any kind. The spells tab is a placeholder with no data behind it.
- Combat, attacks, damage, healing, death saves, rests, exhaustion, and conditions.
- Equipment, inventory effects on stats, armor, and shields.
- Subclasses, feats beyond the background's origin feat, and ability score improvements.
- Multiclassing.
- SRD stat blocks for NPCs. NPC records are unchanged.
- Any replacement for mana. Spell slots arrive with spellcasting.
- Rolling dice on any player-facing surface.
