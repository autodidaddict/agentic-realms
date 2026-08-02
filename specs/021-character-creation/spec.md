# Feature Specification: Interactive Character Creation

**Feature Branch**: `021-character-creation`
**Created**: 2026-08-01
**Status**: Draft
**Input**: User description: "character creation - when a user goes to play for the first time, they should be given an interactive character creation experience. They should be able to supply the character's name, and then select species and class and whatever specializations are available for those. Character backgrounds chosen at level 1 can impact bonuses. Characters should be able to choose the skills to which they will grant bonuses. They will be able to choose which stats (str, dex, con, etc) they will increase. The entire character creation experience should be driven by the information and content contained in the srd_5e library, following the SRD rules. This character creation screen is a modal dialog presented to the user upon their first time entering the game via the play button."

## User Scenarios & Testing *(mandatory)*

Today every player is handed the same generated character: a human fighter with a soldier background, chosen by configuration rather than by the player. This feature replaces that with a creation flow the player drives, presented once, before they ever see a room.

The stories below are ordered so each one is a usable game on its own. Story 1 alone already gives players distinct characters. Each later story adds a decision the SRD allows, and until that story ships the system makes that decision for the player using the same deterministic rules that generate the default character today.

### User Story 1 - Name and identity (Priority: P1)

A player clicks Play for the first time. Before the world loads, a dialog opens and asks who they are. They type a character name, pick a species from the SRD list, pick a class, and pick a background. They confirm, the dialog closes, and they arrive in the starting room as that character. Every remaining decision the SRD allows has been filled in for them with a legal choice.

**Why this priority**: This is the whole point of the feature. A player who only gets this far already stops being an identical copy of every other player, and every later story hangs off these three selections, because species, class, and background are what determine which further choices exist.

**Independent Test**: Register a new account, click Play, complete the dialog with a name and one of each selection, and verify the character sheet shows that name, species, class, and background, with a complete and legal set of ability scores, skills, saves, and hitpoints derived from them, and that the name is what other players in the room see.

**Acceptance Scenarios**:

1. **Given** a player who has never entered the game, **When** they click Play, **Then** the character creation dialog opens over the game screen and the game is not playable behind it.
2. **Given** the dialog is open, **When** the player has not yet supplied a name and all three selections, **Then** the confirm action is unavailable and the dialog says what is still missing.
3. **Given** the player has supplied a name and selected a species, class, and background, **When** they confirm, **Then** the character is created, the dialog closes, and they are placed in the starting room.
4. **Given** a player who already has a character, **When** they click Play, **Then** the dialog does not appear and they enter the world directly.
5. **Given** the player selects a species, **When** the dialog shows that species, **Then** it presents its name, speed, size, and the traits it grants, as published in the SRD content.
6. **Given** the player selects a class, **When** the dialog shows that class, **Then** it presents its hit die, primary ability, saving throw proficiencies, and its level 1 features.
7. **Given** a player has created a character, **When** another player is in the same room, **Then** the character's name is what that other player sees in the room, in speech, in emotes, and in the list of who is present.
8. **Given** a name another character already holds, **When** the player tries to confirm with it, **Then** creation is refused, the dialog says the name is taken, and every other choice is preserved.

---

### User Story 2 - Ability scores and background bonuses (Priority: P2)

The player decides what their character is good at. They assign the SRD standard array across the six abilities, and then choose how the background's ability score increases are spread across the three abilities that background offers, taking either one increase of +2 and one of +1, or three increases of +1. The dialog shows the resulting scores and modifiers as they choose.

**Why this priority**: Ability scores drive nearly every derived number on the sheet, so this is the choice with the widest effect on how the character plays. It comes after story 1 because the background determines which abilities may be increased and the class determines which abilities matter.

**Independent Test**: Create a character, assign the standard array in a non-default order, choose a +2/+1 spread, confirm, and verify the character sheet's six scores equal the assigned array values plus the chosen increases, with modifiers and every dependent value following from them.

**Acceptance Scenarios**:

1. **Given** the ability step, **When** it opens, **Then** each of the six standard array values is assignable to exactly one ability and each ability holds exactly one value.
2. **Given** the player has assigned a value to an ability, **When** they assign that same value elsewhere, **Then** the two abilities swap rather than leaving a value used twice or unused.
3. **Given** the player has chosen a background, **When** they reach the increase step, **Then** only the three abilities that background names are offered.
4. **Given** the player chooses the +2 and +1 spread, **When** they assign it, **Then** the +2 and the +1 go to two different abilities among those three.
5. **Given** the player chooses the three +1 increases, **When** they assign it, **Then** all three of the background's abilities each gain +1 and nothing further is asked.
6. **Given** any assignment, **When** the player looks at the step, **Then** each ability shows its final score and modifier including the increase, not the raw array value.
7. **Given** the player changes their background, **When** increases had already been assigned to abilities the new background does not offer, **Then** those increases are cleared and re-asked rather than silently kept.

---

### User Story 3 - Skill proficiencies (Priority: P3)

The player chooses which skills their character is trained in. The dialog shows the skills the background grants outright, shows how many skills the class lets them choose and from which list, and lets them pick. Skills already granted are visibly accounted for, so a pick is never wasted on something the character already has.

**Why this priority**: Skill proficiency is the choice players feel most directly in play, since it is what the game rolls against. It follows abilities because the modifier a proficiency is added to is what makes one skill a better pick than another.

**Independent Test**: Create a character as a class that offers a choice of skills, pick a set that differs from what the system would pick automatically, confirm, and verify the character sheet marks exactly those skills plus the granted ones as proficient.

**Acceptance Scenarios**:

1. **Given** a class has been selected, **When** the skill step opens, **Then** it offers exactly the number of picks that class allows, from exactly the list that class offers.
2. **Given** a background has been selected, **When** the skill step opens, **Then** the skills that background grants are shown as already held.
3. **Given** a skill is already granted by the background or species, **When** it also appears in the class list, **Then** choosing it is prevented or does not consume a pick, so the character never loses a proficiency to a duplicate.
4. **Given** the player has used all their picks, **When** they select an additional skill, **Then** either the selection is refused with an explanation or an earlier pick is released, and never more than the allowed number is held.
5. **Given** the player changes their class, **When** picks had been made from the previous class' list, **Then** the picks are cleared and re-asked against the new class' list.

---

### User Story 4 - Species and class specializations (Priority: P4)

The player makes the further choices their species and class ask for at level 1. Depending on species that can mean a lineage (an elf's Elven Lineage, a dragonborn's Draconic Ancestry, a gnome's Gnomish Lineage, a goliath's Giant Ancestry, a tiefling's Fiendish Legacy), a size where the species offers more than one, or a feature choice such as a human's extra skill and origin feat. Depending on class it can mean a fighter's Fighting Style and Weapon Mastery, a cleric's Divine Order, or the class' tool proficiency. Species that offer nothing at this tier ask nothing.

**Why this priority**: These are the choices that make two characters of the same species and class feel different. They come last among the choice stories because they are the most varied, and the system can pick a legal option for each of them in the meantime.

**Independent Test**: Create an elf and verify the dialog asks for an Elven Lineage; create a dwarf and verify it asks for no lineage at all; create a fighter and verify it asks for a Fighting Style and three weapon masteries.

**Acceptance Scenarios**:

1. **Given** a species that offers a lineage, **When** it is selected, **Then** the dialog asks for one of that species' lineages and names the trait the choice belongs to.
2. **Given** a species that offers no lineage, **When** it is selected, **Then** no lineage question is shown.
3. **Given** a species that can be more than one size, **When** it is selected, **Then** the dialog asks which size, and otherwise records the species' only size without asking.
4. **Given** a class or species feature that carries a choice available at level 1, **When** that class or species is selected, **Then** the dialog asks that choice with the options the SRD content lists for it.
5. **Given** a class whose subclass arrives above level 1, **When** the player creates a level 1 character, **Then** no subclass is asked for and the dialog says at which level it will be chosen.
6. **Given** the player changes their species or class, **When** specialization choices had been made for the previous one, **Then** those choices are discarded and the new one's choices are asked.

---

### User Story 5 - Review before committing (Priority: P5)

Before confirming, the player sees the whole character as it will exist: name, species, class, background, the six scores with modifiers, hitpoints, armor class, initiative, proficiency bonus, saving throws, skills, and the features and feats they will have. They can go back to any earlier step, change something, and see the summary update. Nothing is created until they confirm.

**Why this priority**: This is confidence rather than capability. Every other story can ship and be played without it, but a player making a permanent decision deserves to see it whole first.

**Independent Test**: Step through creation, open the review, go back and change the class, return to the review, and verify hit die, hitpoints, saving throws, and class features all reflect the new class.

**Acceptance Scenarios**:

1. **Given** all required choices are made, **When** the player opens the review, **Then** every value the character sheet will show is shown, computed by the same rules the sheet uses.
2. **Given** the player is on the review, **When** they go back and change a choice, **Then** the review reflects the change without the player having to redo unrelated choices.
3. **Given** the player is on the review, **When** they have not confirmed, **Then** no character exists and abandoning the page leaves them with none.
4. **Given** the player confirms, **When** creation succeeds, **Then** the character is exactly what the review showed.

---

### Edge Cases

- A player closes the browser or navigates away partway through creation. Nothing has been committed, so the next visit starts the dialog over from the beginning.
- A player opens the game in two tabs before creating a character. Both show the dialog; whichever confirms first creates the character, and the other is told a character already exists and is taken into the world rather than creating a second.
- Two nodes handle those two tabs. Exactly one character is created, and the second attempt is a no-op rather than an error the player sees.
- A player submits an empty name, a name of only whitespace, or a name longer than the allowed length. The dialog refuses and says why, without losing any other choice already made.
- A player picks a name another character already uses, or the same name in different case. Creation is refused with a message saying the name is taken, and every other choice survives so only the name has to change.
- Two players confirm the same free name in the same instant. Both may succeed, by design (FR-013). Nothing crashes and neither player sees an error; the world briefly holds two characters with one name.
- A name is shown as available while the player finishes the rest of creation, and is taken by someone else before they confirm. The refusal happens at confirmation and is explained; availability shown earlier is a courtesy, not a reservation.
- A player selects a class, makes skill and specialization choices, then changes the class. Dependent choices are cleared and re-asked; the name, species, and background survive.
- A background's origin feat and a human's Versatile feat pick are the same feat. The character holds the feat once, and the duplicate pick does not silently disappear without the player being told.
- A class' skill list and the background's granted skills overlap so far that fewer distinct skills remain than the class allows picks from. The player can still reach a complete character.
- A player reaches the review with an incomplete choice somewhere earlier. Confirm stays unavailable and the review names the step that is incomplete.
- A player selects a species offering ten lineages. Every option is reachable, including on a small screen.
- Confirmation fails on the server, for example because the world is briefly unreachable. The dialog stays open with every choice intact and the player can retry.
- A player who created a character before this feature existed returns. Their existing character stands and the dialog does not appear.

## Requirements *(mandatory)*

### Functional Requirements

**Presentation and gating**

- **FR-001**: The system MUST present character creation as a modal dialog when a player enters the game and has no character, and MUST NOT present it when they already have one.
- **FR-002**: The system MUST prevent play while the dialog is open. The world behind it MUST NOT accept commands, and the dialog MUST NOT be dismissable without either creating a character or leaving the game.
- **FR-003**: The system MUST NOT create, persist, or announce any part of a character until the player confirms.
- **FR-004**: The system MUST create at most one character per player, no matter how many times creation is confirmed, from however many tabs, sessions, or nodes.
- **FR-005**: On confirmation the system MUST place the player in the world the same way it does today, with no additional step the player has to take.

**Content and rules**

- **FR-006**: Every option the dialog offers MUST come from the SRD content library. The game MUST NOT hold its own list of species, classes, backgrounds, skills, abilities, lineages, feats, or features, and MUST NOT reimplement any SRD calculation.
- **FR-007**: The system MUST offer only choices the SRD grants at level 1, and MUST NOT ask for a choice the SRD defers to a higher level. Where a choice is deferred, the dialog MUST say at what level it arrives.
- **FR-008**: The system MUST reject any confirmation whose choices are not legal under the SRD content, independently of what the dialog allowed the player to click.
- **FR-009**: Adding new species, classes, backgrounds, lineages, feats, or features to the SRD content library MUST make them available in creation without any change to the creation flow itself.

**Name**

- **FR-010**: Players MUST be able to supply a character name, and the system MUST persist it as part of the character.
- **FR-011**: The system MUST require a name that is non-empty after trimming surrounding whitespace and no longer than 32 characters, and MUST reject anything else with a message saying what is wrong.
- **FR-012**: The system MUST check, at confirmation, that no other character already holds the name, comparing without regard to case, and MUST refuse a confirmation whose name is taken while preserving every other choice the player made.
- **FR-013**: The check is not a reservation. Two players confirming the same free name within the same instant MAY both succeed, and the system is NOT required to prevent it. The consequence is cosmetic — two characters share a name, and addressing one of them by name is ambiguous until a rename — and preventing it would cost either a two-phase creation with a compensating command or a reservation table written outside a projector, neither of which is worth carrying for a collision this rare.
- **FR-014**: The character name MUST be the player's public identity throughout the world, replacing the account username wherever the world names a player: the character sheet, room descriptions and occupant lists, speech, emotes, whispers and tells, and presence.
- **FR-015**: The account username MUST remain the login credential and MUST NOT be shown to other players.

**Species, class, background**

- **FR-016**: Players MUST be able to select exactly one species, one class, and one background, and MUST NOT be able to confirm without all three.
- **FR-017**: For each option offered, the system MUST show enough detail to choose between them: for species its size, speed, and traits; for class its hit die, primary ability, saving throws, and level 1 features; for background the abilities it can raise, the skills it grants, and the origin feat it grants.
- **FR-018**: Players MUST be able to change any selection before confirming, and the system MUST clear and re-ask exactly the dependent choices that selection invalidates, leaving independent choices intact.

**Ability scores**

- **FR-019**: Players MUST be able to assign the SRD standard array across the six abilities, with each value used exactly once.
- **FR-020**: Players MUST be able to choose how their background's ability score increases are spread, among the spreads the SRD allows, across only the abilities that background names.
- **FR-021**: The system MUST show, for each ability, the final score and modifier including the background increase.
- **FR-022**: The system MUST NOT allow any level 1 ability score to exceed the SRD's maximum of 20.

**Skills and specializations**

- **FR-023**: Players MUST be able to choose the skill proficiencies their class offers, in the number that class allows, from the list that class offers.
- **FR-024**: The system MUST show which skill proficiencies the background and species grant outright, and MUST NOT let a class pick be spent on a skill the character already holds.
- **FR-025**: Players MUST be able to make every other choice their selected species and class ask for at level 1, including lineage, size where more than one is offered, tool proficiency, and any level 1 feature that carries a choice.
- **FR-026**: The system MUST ask no question for a species or class that offers no choice at a given tier.
- **FR-027**: The resulting character MUST hold each proficiency, feat, and feature exactly once, however many sources granted it.

**Review and creation**

- **FR-028**: Players MUST be able to review the complete character, showing every value the character sheet will show, before confirming.
- **FR-029**: The reviewed character and the created character MUST be identical.
- **FR-030**: A created character MUST be at level 1 with zero experience and at full hitpoints.
- **FR-031**: The system MUST record the character's choices as facts, so that later changes to SRD content or to game configuration do not retroactively alter a character that already exists.
- **FR-032**: If creation fails, the dialog MUST stay open with every choice intact, and the player MUST be able to retry without re-entering anything.

**Out of scope**

- **FR-033**: The system MUST NOT ask for starting equipment. Characters are created carrying nothing, as they are today. The SRD's class and background equipment bundles are deliberately left unasked until SRD items and the game's own item blueprints are reconciled, which is its own feature.

### Key Entities

- **Character Draft**: The in-progress set of choices, held only for the duration of the dialog and never persisted. Holds the name and every selection made so far, plus which choices remain open. Discarded if the player leaves without confirming.
- **Character**: What is created on confirmation and persists for the life of the player: name, species, class, background, size, the six ability scores, skill proficiencies, saving throw proficiencies, feats, chosen lineage and feature options, level, experience, and hitpoints. Everything else on the sheet is derived from these rather than stored.
- **Species**: An SRD species, carrying its name, size options, speed, traits, and the lineages it offers. Supplied by the content library.
- **Class**: An SRD class, carrying its name, hit die, primary ability, saving throw proficiencies, the skills it offers a choice of, its tool proficiency, and the features it grants at each level, including which of them carry choices. Supplied by the content library.
- **Background**: An SRD background, carrying the three abilities it can raise, the origin feat it grants, the two skills it grants, and its tool choice. Supplied by the content library.
- **Choice**: One decision the character makes: how many to pick, and the options to pick from. Species lineages, class skills, fighting styles, weapon masteries, and feature options are all this same shape, which is what lets the dialog present a new one without knowing what it is.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A player who knows what they want can complete character creation in under three minutes.
- **SC-002**: A player creating their first character can complete it without consulting any rules reference outside the dialog, because every option carries the detail needed to choose between them.
- **SC-003**: 100% of confirmed characters are legal SRD level 1 characters, verified against the rules content rather than against the dialog that produced them.
- **SC-004**: Every species, class, and background in the content library is selectable, and every level 1 choice each of them carries is presented. No option is unreachable.
- **SC-005**: Every option shown, and every number computed during creation, traces to the SRD content library. No species, class, background, skill, ability, feat, or calculation is duplicated in the game.
- **SC-006**: 100% of players entering the game for the first time see the dialog, and 0% of returning players see it.
- **SC-007**: Never more than one character exists per player, including when two sessions confirm at the same moment.
- **SC-008**: Adding a new species or class to the content library makes it appear in creation with no change to the creation flow.
- **SC-009**: Abandoning creation at any point leaves no trace: the player has no character, and their next attempt starts clean.
- **SC-010**: Of characters created by different players, at least 90% differ from one another in species, class, background, or ability spread, against today's baseline of 0% where every character is identical.
- **SC-011**: A name already held is refused at confirmation, ignoring case, in every case except a genuine same-instant race, which FR-013 permits.
- **SC-012**: No account username is visible to any player other than its owner, anywhere in the game.

## Assumptions

- **Standard array only.** Ability scores are assigned from the SRD standard array. Rolling and point buy are out of scope; the standard array is what the content library exposes and it is the SRD's default.
- **Level 1 only.** Creation produces a level 1 character. Choices the SRD grants above level 1, subclasses among them, arrive through levelling and are not part of this feature.
- **No pre-existing characters to handle.** The event log is destroyable in the current phase and the world is reseeded, so no migration path for the configuration-generated characters is needed. The gate is nonetheless written as "has no character" rather than "is a new account", so any character that does exist is left alone.
- **Creation happens once.** There is no re-roll, rename, or respec. Those are separate features if they are ever wanted.
- **The dialog replaces generation, it does not sit beside it.** Once this ships, the configured default character is no longer how players get a character. Deterministic generation from the same rules is still useful for tests, seeds, and for filling choices a not-yet-shipped story does not ask about.
- **Drafts are not persisted.** An abandoned creation leaves nothing behind, which keeps a half-made character from ever being mistaken for a real one.
- **Nothing in this feature coordinates across nodes.** A draft belongs to one player's one session and is never read from anywhere else, and the name check is a plain read of the projection. There is no cluster-wide invariant here, which is a deliberate consequence of FR-013 rather than an oversight: making names strictly unique is the one thing that would have introduced one.
- **The starting room and spawn behaviour are unchanged.** Creation happens before the existing entry into the world and does not alter it.
- **The character name becomes the world's name for a player.** Every place that prints a username today prints the character name instead, and this feature carries that change rather than deferring it. The username survives as a login credential and nothing else.
- **Uniqueness is checked at confirmation, not reserved during creation.** Showing a name as available while the player finishes the rest of creation is a courtesy; the authoritative check is the one that runs when they confirm.
- **Equipment is a separate feature.** Creation asks nothing about gear. The work in starting equipment is mapping SRD item slugs onto the game's item blueprints and spawning real entities, not the picker, so it is not smuggled in here.
- **Content is the source of truth for presentation too.** Trait text, feature descriptions, and option names shown in the dialog come from the content library, so the dialog does not carry its own copy of any rules prose.
