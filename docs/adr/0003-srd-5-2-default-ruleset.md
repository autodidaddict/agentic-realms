# 3. SRD 5.2 as the Default Ruleset (5.1 Divergences as Explicit Opt-Ins)

- **Status**: Accepted
- **Date**: 2026-07-19
- **Deciders**: Kevin Hoffman
- **Related**: ADR-0002 (roll our own combat resolution, modeled on the SRD); the
  D&D System Reference Documents 5.1 and 5.2, both CC-BY-4.0; the `srd_5e`
  package. Supersedes the SRD-version choice in ADR-0002.

## Context

ADR-0002 said we'd model the engine on the SRD and named SRD 5.1. That was a
default, not a choice weighed against the alternative — SRD 5.1 is the 2014 rules
and the version most third-party content targets, so it was the reflexive "the
SRD." But SRD 5.2, the 2024-rules revision, is the current version and is also
published under CC-BY-4.0. We want the latest rules as the baseline.

The two share the core: the d20 test, attack rolls, damage, hit points, saving
throws, and ability checks resolve identically. They diverge in a small,
enumerable set of rules — Exhaustion was reworked (5.2 is a flat penalty per
level; 5.1 uses a per-level ladder), Weapon Mastery is 5.2-only, and there are
scattered crit and condition tweaks — and in their content data (weapons, armor,
spells, monsters).

## Decision

SRD 5.2 is the default ruleset for `srd_5e`. Where 5.1 differs on a specific rule,
that behavior is available as an explicit opt-in, not a separate mode.

- The shared core carries no version parameter, because there's nothing to choose.
- The functions that actually diverge take an `edition:` option defaulting to
  `:srd_5_2`; passing `:srd_5_1` selects the older behavior for that call. So 5.1
  behavior is always named explicitly and never happens by accident.
- The set of divergences is kept as a short, documented list, so it stays a
  handful of named exceptions rather than a versioning framework.
- Content is 5.2. Shipping a wholesale 5.1 content set is out of scope for this
  decision; the per-rule opt-in covers rules, not data.
- A consumer that wants to run entirely in 5.1 defaults the `edition:` in its own
  wrapper; the library itself stays per-call explicit.

This supersedes the SRD-version choice in ADR-0002. Everything else in ADR-0002 —
roll our own resolution, no third-party rules or dice dependency — stands.

## Consequences

**Positive**

- The baseline is the current rules, and 5.2's formal vocabulary (the "D20 Test")
  matches what the code already calls `Srd.Rules.D20`.
- 5.1 behavior is opt-in and local, so a 5.2 game can't drift into 5.1 rules
  silently.
- The version surface stays tiny — only the diverging functions know about
  editions.

**Costs**

- We maintain a documented list of the divergences and their `edition:` options,
  and keep it correct as errata land.
- Content is 5.2 only; a 5.1 content set would be a separate, larger effort.
- Attribution now credits two documents.

## Attribution

Because the engine models SRD 5.2 and incorporates specific 5.1 rules, the package
credits both under CC-BY-4.0:

- SRD 5.2 (primary), available at https://www.dndbeyond.com/srd
- SRD 5.1 (for the incorporated divergent rules), available at
  https://dnd.wizards.com/resources/systems-reference-document

## Alternatives considered

- **Stay on SRD 5.1.** Rejected: it isn't the current version, and it was only
  ever a default rather than a considered choice.
- **Support 5.1 and 5.2 as equal, parallel rulesets.** Rejected: that means a
  versioning framework and a doubled content set for what is, on the rules side, a
  small number of differences. A 5.2 baseline with per-rule opt-ins is far
  lighter.
- **A global ruleset mode instead of per-call opt-ins.** Rejected: heavier than
  the problem needs, and a consumer wanting a global lean can default it in its
  own layer.
