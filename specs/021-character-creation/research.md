# Phase 0 Research: Interactive Character Creation

**Feature**: 021-character-creation | **Date**: 2026-08-01 | **Plan**: [plan.md](./plan.md)

Ten decisions. The spec left no `NEEDS CLARIFICATION` markers, so none of these resolve an open
question from the spec; they settle the design questions the spec's requirements raise.

---

## R1. Where "what must be decided" lives

**Decision**: Add two pure functions to `srd_5e`: `Srd.Character.choices/1`, which returns every
open pick-N-of-M decision for a species, class, and background at a level, and
`Srd.Character.grants/1`, which returns what those three grant outright. Add `:size` to
`Srd.Content.Choice`'s permitted kinds so a species' size choice comes back in the same shape as
every other one.

**Rationale**: FR-006 forbids the game from holding its own list of anything, and FR-009 requires
new content to appear in creation with no change to the creation flow. Both only hold if the
question "what does this character still have to decide?" is answered by the package. Answering
it in the game means walking `species.features`, `species.lineages`, `species.sizes`,
`class.skill_choice`, `class.tool_proficiency`, and `class.features` by hand, which is precisely
the SRD knowledge FR-006 says the game must not carry, and it breaks the moment content grows a
choice in a place the walker did not look.

ADR-0004 does not need amending for this, and that is worth stating plainly because it looked
like it might. The ADR's line is "the library answers what may be chosen, never what has been
chosen", and it rejected shipping "an `Srd.Character` that holds choices and validates a finished
build". `choices/1` holds nothing and validates nothing: selections in, options out, which is the
ADR's stated purpose applied across the five content types instead of one at a time. It is the
same shape as the `Feats.eligible/1` the ADR already blesses.

**Alternatives considered**:

- *Walk the content in the game.* Rejected: it puts SRD structure in the consumer, which is what
  FR-006 forbids, and it is the one design where adding a species with a new kind of trait
  silently drops that trait from creation.
- *Add `Srd.Character.validate/1` to the package as well.* Rejected, and see R8. The game can
  validate a submission without knowing any rules, by checking each pick against the options
  `choices/1` offered. Adding a validator would be the "validates a finished build" that ADR-0004
  turned down, and it would buy nothing the set comparison does not already give.
- *A `Srd.Character.Builder` holding a partial build.* Rejected outright by ADR-0004, and the
  draft belongs in the LiveView anyway (R5).

---

## R2. How name uniqueness is enforced

**Decision**: It is not. `Commands.create_character/2` checks the projection for a name already in
use and refuses if it finds one. Two players confirming the same free name in the same instant may
both succeed, and nothing prevents it.

**Rationale**: A hard guarantee needs something atomic across the cluster, and both ways of getting
one cost more than the problem they solve.

A uniqueness aggregate — keying an aggregate by the normalized name, so Commanded's per-stream
serialization does the work — is the textbook answer, and it is what this codebase already does for
blueprint slugs. But a blueprint *is* its slug, so the unique value and the aggregate key are the
same thing and the guarantee is free. A character is keyed by its player, so the same trick needs a
*second* aggregate, which turns creation into two dispatches with a compensating command and a claim
that outlives a node dying between them. That is a two-phase commit with a known hole, for one
string field.

A reservation table with a unique index is cheaper and fails better — cleanup is a `Repo.delete` in
the same function rather than a command that can be lost — but it still means write-side state
maintained outside a projector, plus a table and a migration to carry.

What either buys is preventing a collision that requires two players to confirm the same name within
milliseconds of each other. The consequence if it happens is that two characters share a name and
addressing one of them by name is ambiguous until a rename. That is cosmetic, and cheaper to fix by
hand on the day it happens than to carry the machinery that prevents it.

**Alternatives considered**:

- *A `CharacterName` aggregate keyed by the normalized name.* Built, then removed. Correct, and the
  most idiomatic thing in a pure event-sourcing sense, but see above: two dispatches, a compensating
  command, and an orphaned claim when a node dies mid-flight.
- *A reservation table with a unique index, written by the facade and rebuilt by a projector.* The
  best of the guaranteeing options, and what to reach for if names ever have to be strictly unique.
  Rejected now because the guarantee is not worth a table.
- *A unique index on `player_state.character_name` alone.* Rejected outright: the violation surfaces
  inside the projector, where it halts the projection for every player rather than returning an
  error to the one who lost.

---

## R4. Replacing the username with the character name

**Decision**: The world stops reading `accounts.players.username` entirely. A single lookup,
`AgenticRealms.World.PlayerNames`, answers "what is this player called" from
`player_state.character_name`, and the world-facing map keys are renamed to match what they now
hold: `username` becomes `name` in the maps `World.Queries` returns, and `actor_username` becomes
`actor_name` in the `World.UIEvents` structs.

**Rationale**: FR-014 makes the character name the player's public identity everywhere and FR-015
keeps the username private. The mechanical part is small, because name resolution is already
funnelled through a handful of seams:

| Seam | Today | After |
|---|---|---|
| `World.Queries.list_players_in_room/1`, `list_other_players/2` | joins `accounts.players`, selects and orders by `p.username` | selects and orders by `ps.character_name`, dropping the join |
| `World.UIEventBroadcaster.lookup_username/1` | `Accounts.get_player/1` | `PlayerNames.get/1` |
| `World.Stats.player_name/1` | `Accounts.get_player/1` | the `player_state` row it has already read |
| `World.Examine.acting_username/1` and its matchers | `Accounts.get_player/1` | `PlayerNames.get/1` |
| `World.Communication` sender map, `RecipientResolver` | username in, username matched | name in, name matched |
| `AgenticRealmsWeb.Presence.track_player/3` | `current_player.username` from mount | the character name |
| `World.NpcChat.Context`, `World.IntentResolver.ContextSnapshot` | username | name |

The rename is the larger half of the change, and it is deliberate. A map key called `username`
holding a character name is a lie that every later reader pays for, and `mix precommit` plus the
test suite catch the propagation. The external NPC API needs no contract change at all: the
surroundings endpoint already renames the field to `name` on the way out
(`npc_service_controller.ex:127`), so the published shape is unchanged and only its source moves.

**Alternatives considered**:

- *Populate the existing `username` keys with the character name and rename nothing.* Rejected: it
  is a one-line change that leaves every consumer reading a field whose name is wrong, and the
  next person to add a caller will pass a real username into it.
- *Defer the rename to a follow-up.* Rejected: this was offered during `/speckit.specify` and the
  user chose the full change now. Splitting it would ship a known-inconsistent world.

---

## R5. Where the draft lives

**Decision**: In the LiveView's socket assigns, as an `AgenticRealms.World.CharacterDraft` struct.
Never persisted, never broadcast, never in a registry.

**Rationale**: A draft belongs to one player's one session and is meaningless to any other process
on any other node, which is exactly the node-local state Principle I permits. Not persisting it
satisfies FR-003 and FR-032's "abandoning leaves no trace", and it removes any chance of a
half-made character being mistaken for a real one. The struct lives in the `World` context rather
than in the web layer because the validator that guards the dispatch (R8) works on it and the
command facade is where it is turned into commands.

**On Principle III**: every selection in the dialog is a server round trip, and that needs stating
because the character sheet's tabs in feature 020 were explicitly kept off the server. The two are
different. A sheet tab shows a panel that was already rendered, so the server has nothing to add.
A species selection changes *which questions exist* — pick an elf and a lineage question appears,
pick a dwarf and it does not — and the answer comes from compile-time content that lives on the
server. Rendering that in the browser would mean shipping the content library to the client. The
round trip buys the next step's options, which is the "data the client must not hold" case the
principle allows. It is one round trip per click, off any hot path, with no world state touched.

The name availability check is the other round trip, and it needs the database by definition. It
runs debounced on the name field rather than on every keystroke.

**Alternatives considered**:

- *Persist the draft so a player can resume.* Rejected: it contradicts FR-003, and a resumable
  draft is a second kind of half-character to keep straight for a flow that takes three minutes.
- *Hold the draft in the browser and post it whole.* Rejected: the client would need the content
  library to know what to ask next.

---

## R6. Rendering before a character exists

**Decision**: `GameLive` gains a `:phase` assign, `:creating` or `:playing`. Everything mount does
today after the character exists moves into a private `enter_world/1`. Mount calls it when the
player has a character and otherwise assigns `phase: :creating` with a fresh draft. The template
branches on the phase: `:creating` renders the app shell with a dimmed, inert game pane and the
creation modal over it; `:playing` renders exactly what it renders today. On confirmation the
handler dispatches, then calls `enter_world/1` and flips the phase.

**Rationale**: Mount currently spawns the player and loads a room before assigning anything, and
roughly thirty assigns depend on that room existing. Making every one of them nil-tolerant so the
existing template can render behind the modal would spread the change across the whole game view
for a state that lasts three minutes once per player. A phase branch confines it: nothing in the
playing path changes, and the creating path renders a deliberately empty pane, which is also the
most honest rendering of FR-002's "the world behind it is not playable" — there is no world behind
it yet.

Extracting `enter_world/1` is worth doing on its own. Mount is currently one function that spawns,
queries, subscribes, fires arrival behaviors, and assigns; the confirm handler needs all of it,
and duplicating it would guarantee the two drift.

**Alternatives considered**:

- *A separate `CharacterCreationLive` at its own route.* Rejected: the spec asks for a modal on the
  play screen, and a redirect dance adds a navigation the player did not ask for.
- *Spawn the player into the starting room first and create the character behind the modal.*
  Rejected: it puts a player with no character in a room where other players can see them, and
  `Stats.for_player/1` raises for exactly this state.

---

## R7. What a character's picks are stored as

**Decision**: Keep the typed columns feature 020 added (`skill_proficiencies`,
`save_proficiencies`, `feat_slugs`, the six scores) because they are the facts
`Srd.Character.derive/1` consumes. Add `character_name`, `lineage_slug`, and one `choices` map
column holding the picks that have no typed home: tool proficiencies, weapon masteries, and
feature options such as a cleric's Divine Order. The map is keyed by the stable choice key
`Srd.Character.choices/1` assigns.

**Rationale**: Skill picks and feat picks already flatten into columns the read path uses, and
moving them would rewrite the working `Stats.for_player/1` adapter for no gain. The remaining picks
have no consumer yet, because nothing in the game uses a weapon mastery or a Divine Order, but they
are the player's choices and FR-029 requires the created character to be what the review showed.
Dropping them on the floor would make the review a lie. A single map column takes them all without
a column per rule, and it accepts new kinds of choice without a migration, which is what FR-009
needs on the storage side as much as on the presentation side.

**Alternatives considered**:

- *Store only the choices map and assemble the typed facts on every read.* Rejected: it is the
  purer model, but it rewrites a read path that works today and puts assembly on every sheet load.
  Worth revisiting if the map grows a second consumer.
- *A column per kind of pick.* Rejected: a migration for every new choice the SRD content gains
  breaks FR-009's promise.
- *Drop the picks with no mechanical consumer.* Rejected: it silently discards what the player
  chose and contradicts FR-029.

---

## R8. How a submission is validated

**Decision**: `AgenticRealms.World.CharacterDraft.validate/1` re-asks the package what was legal
and checks the submission against the answer. For every choice `Srd.Character.choices/1` returns,
it checks that the draft holds the right number of picks and that each one appears in that choice's
options. Ability scores are checked against `Srd.Rules.Ability.standard_array/0` for a permutation,
against `Srd.Content.Background.spreads/0` and the background's `ability_scores` for the increase,
and against the SRD's cap of 20. The name is checked for length and emptiness.

**Rationale**: This satisfies FR-008 without the game learning a single SRD rule. The validator
never knows what a fighting style is; it knows that the submitted slug has to be in the list the
package offered. That is what makes FR-009 true on the validation side too — a new kind of choice
validates correctly the day it is added, because the check is set membership against whatever came
back.

Running it before dispatch, in the facade, keeps the aggregate free of content lookups, which is
the same rule feature 020 set for `CreateCharacter`: the command carries a finished character and
the aggregate generates and defaults nothing.

**Alternatives considered**:

- *Validate in the aggregate.* Rejected: it makes the aggregate read compile-time content at
  `execute/2` time, which is the coupling feature 020 removed on purpose.
- *Trust the dialog.* Rejected by FR-008, and rightly — the dialog is a client.

---

## R9. What happens to `CharacterGen`

**Decision**: `World.CharacterGen` stays, and the `:character_defaults` configuration with it. It
stops being how players get a character and becomes how the *unasked* choices get filled: while
stories 2 through 4 are unshipped, the dialog asks only what has shipped and generation supplies
the rest. It also stays the fixture behind seeds and tests.

It gains `complete/1`, which takes a draft and returns one with every open decision settled, filling
only what is missing. **The facade calls it before validating** (data-model §6), which is the step
that makes the story ordering work: a draft carrying only a name, species, class, and background is
a complete character by the time the validator sees it. Without that step nothing could be created
until story 4 shipped, because the validator's rules are unconditional by design.

**Rationale**: The spec's story ordering only works if each story can ship alone, and story 1 alone
means a player picks a species, class, and background while something still has to choose their
ability spread and their skills. That something already exists, is already deterministic, and is
already tested. Deleting it would mean writing it again, worse, inside the dialog.

`ensure_character/1` is what goes away, since the interactive path replaces the automatic one.

**Alternatives considered**:

- *Delete `CharacterGen` and require every story at once.* Rejected: it collapses five
  independently shippable stories into one, which the spec's structure exists to avoid.
- *Keep `ensure_character/1` as a fallback.* Rejected: two ways for a character to come into being
  is exactly the ambiguity FR-004 is trying to remove.

---

## R10. Starting equipment

**Decision**: Out of scope, per the user's answer during `/speckit.specify`, and recorded as
FR-033 rather than left unsaid.

**Rationale**: The work in starting equipment is not the picker. It is mapping SRD item slugs onto
the game's item blueprints and spawning real entities into a player's inventory through the feature
016 containment path. That is a feature, and bolting it onto this one would double the size of a
flow whose value is the choices, not the gear.

---

## Summary of what this adds

| Where | What |
|---|---|
| `srd_5e` | `Srd.Character.choices/1`, `Srd.Character.grants/1`, `:size` as a `Choice` kind |
| Write side | `CreateCharacter` and `CharacterCreated` extended. No new aggregate, command, or event. |
| Read model | `player_state.character_name`, `.lineage_slug`, `.choices`; an index on `lower(character_name)` |
| Game | `CharacterDraft` (struct + validator), `CharacterGen.complete/1`, `PlayerNames`, the facade's `create_character/2` |
| Web | The creation modal, `GameLive`'s `:creating` phase, `enter_world/1` |
| Everywhere | Username replaced by character name as the player's public identity |
