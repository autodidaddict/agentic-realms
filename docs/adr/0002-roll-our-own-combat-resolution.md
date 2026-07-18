# 2. Roll Our Own Combat Resolution (No Third-Party Rules Dependency)

- **Status**: Accepted
- **Date**: 2026-07-18
- **Deciders**: Kevin Hoffman
- **Related**: ADR-0001 (combat mechanics are core Elixir); features 019 (real
  stats), 018 (external NPC brains); Constitution Principles II
  (Event-Sourcing Invariants), IV (Test-First), VI (Deliberate Simplicity); the
  D&D System Reference Document 5.1 (CC-BY-4.0); the planned combat feature
  (spec-020).

## Context

Turn-based combat is next, and two earlier decisions already say where the
resolution logic has to live.

ADR-0001 put combat mechanics (damage, death, XP-on-kill) in the core,
server-authoritative, event-sourced Elixir. The remote brain only decides
whether to fight or flee; it never runs the mechanic. So the resolution layer is
trusted, in-cluster Elixir no matter what we build it from.

Feature 019 gave players and NPCs SRD-shaped stats (six ability scores, level,
HP), so the natural rules system is the D&D 5e SRD. Wizards of the Coast
publishes it under Creative Commons Attribution 4.0 (CC-BY-4.0), which is
permanent, irrevocable, allows commercial use, and asks only for attribution.
Implementing and adapting SRD mechanics is allowed.

The question this ADR answers is build vs. buy: do we write the resolution layer
ourselves or take a dependency?

We searched hex.pm on 2026-07-18. There is no D&D 5e SRD combat-resolution
library for Elixir:

- `ex_ttrpg_dev` (the closest, and it ships a `dnd_5e_srd` system) and `ex_rpg`
  cover character generation, ability checks, dice, and loading system data, but
  neither resolves combat. Both are AGPL-3.0.
- `rpg` is an incomplete, unmaintained "RPG engine," and it is UNLICENSED (no
  usage rights granted).
- The only mature, permissively-licensed packages are dice-notation rollers
  (`dicex`, `ex_dice_roller`). They evaluate expressions like `2d6+3` and nothing
  more.

Four things settle the decision:

1. The resolution has to be pure functions we can unit-test without the database
   (Principle IV).
2. Every roll's actual result has to be captured into the event it produces,
   because the aggregate rolls once at command time and never re-rolls on replay
   (Principle II). A library that owns its own randomness and mutates state works
   against this.
3. A new runtime dependency has to earn its place against the standard library
   and what we already depend on (Principle VI).
4. AGPL would put its license terms on our whole application, which does not work
   for this product.

## Decision

Write the combat resolution ourselves, as pure Elixir, with no third-party rules
or dice dependency. Model the mechanics on the D&D SRD 5.1.

Two pure modules:

- `AgenticRealms.World.Combat.Dice` — a small roller over `:rand` that returns
  the individual dice and the total, so the aggregate can record the full result
  in the event.
- `AgenticRealms.World.Combat.Rules` — the SRD resolution: attack rolls against
  Armor Class, damage, saving throws, conditions, initiative, and death saves. No
  database, deterministic once the dice are rolled, tested first against the SRD's
  own examples.

Resolution runs inside the trusted, event-sourced core, as ADR-0001 requires. The
pure functions work out the outcome; the Encounter aggregate rolls at command
time, records the values in the events, and stays the sole writer. The Encounter
aggregate's own design belongs to spec-020; this ADR only settles build vs. buy
and the module boundary.

Start with the essential mechanics: attacks, damage, saves, conditions,
initiative, death saves. Everything broader (spells, monster stat blocks, class
features) is authored data on top of that engine, not more code, which matches
how blueprints and behaviors already work.

For any future combat dependency: take one only if it is permissively licensed
and does not own randomness or state in a way that breaks roll-capture or purity.
Otherwise we build it. Dice rolling on its own is not a reason to add a
dependency. It is a few lines of standard library, and owning it is what lets us
record each die for replay.

Because we model on the SRD, the project credits carry WotC's required notice:

> This work includes material taken from the System Reference Document 5.1
> ("SRD 5.1") by Wizards of the Coast LLC and available at
> https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is
> licensed under the Creative Commons Attribution 4.0 International License,
> available at https://creativecommons.org/licenses/by/4.0/legalcode.

We take SRD content straight from WotC's CC-BY release, not from an AGPL
repackaging of it. We do not use trademarks or Product Identity (the D&D name,
the logo, the setting-specific monsters and places); the game keeps its own
names.

## Consequences

Positive:

- We control how rolls are captured, which keeps the event log replay-safe.
- Pure functions mean fast unit tests and an easy green-before-merge.
- No new runtime dependency, no AGPL obligations, no risk from an unmaintained
  package.
- The rules are ours to adjust, including places we choose to differ from the SRD
  (019's mana instead of spell slots, for one), without working around a library.
- Attribution is the only licensing obligation, and there is no trademark
  exposure.

Costs:

- We write, test, and maintain the SRD mechanics, and the SRD is large. Starting
  small and pushing breadth into data keeps this manageable.
- We do not get community-maintained rules updates; porting later SRD revisions is
  our own work.
- We could drift from correct SRD math. Testing against the SRD's own examples is
  the guard.

If a solid, permissively-licensed Elixir SRD engine shows up later, we can revisit
this and supersede the ADR.

## Alternatives considered

- Depend on `ex_ttrpg_dev` or `ex_rpg`. Neither resolves combat, and both are
  AGPL-3.0, which would put copyleft on the whole product.
- Depend on `rpg`. It is UNLICENSED and unmaintained.
- Take only a dice-notation roller and write the rules ourselves. Not worth it:
  rolling dice is trivial standard library, and owning it is what gives us the
  per-die results the events need. A dependency here does not clear Principle VI.
- Switch to a different game system that has a ready-made Elixir engine. The SRD
  is the fidelity we want, it is CC-BY, and it already fits the 019 stats.
- Use the SRD under the OGL 1.0a instead of CC-BY-4.0. CC-BY is simpler and
  irrevocable and asks only for attribution.
- Hand resolution to the remote brain or an external service. ADR-0001 already
  rules this out: mechanics are core, sole-writer Elixir.
