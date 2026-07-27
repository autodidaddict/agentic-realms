# Changelog

The format is based on Keep a Changelog, and this project follows Semantic
Versioning.

## [Unreleased]

Character-creation content: what a character may be, and what may be chosen at
each point. See ADR-0004.

- Content: SRD 5.2 classes, subclasses, species, backgrounds, feats, and the
  items that starting equipment refers to, loaded from data at compile time and
  looked up by slug.
- `Srd.Content.Choice` and `Srd.Content.Feature` are the two shapes every
  content type shares, so one traversal covers all of them.
- Filtering answers what may be chosen: `Subclasses.for_class/1`,
  `Feats.eligible/1` over machine-readable prerequisites,
  `Classes.multiclass_options/1`, and an `all/1` taking field filters on every
  collection, including weapons and armor.
- Cross-references between content are checked while compiling, so a mistyped
  slug is a build failure.
- Spells are deliberately not here; they are large enough to belong in an
  optional package of their own. Casters are described but not complete.

## [0.2.0]

First working release, modeling SRD 5.2 by default with 5.1 rules as explicit
opt-ins.

- Dice: parse and roll dice notation, tagged reducers (sum, max, min,
  drop-lowest), a `Srd.Dice.Roll` result, and named roll constructors in
  `Srd.Dice.Rolls`.
- Rules: the d20 test and its faces (`Attack`, `Save`, `Check`); `Damage` with
  the 13 damage types and resistance/vulnerability/immunity; `Hitpoints` with
  temporary hit points, clamping, and downed/dead/recovered outcomes;
  `DeathSaves`; and `Initiative`.
- Content: SRD 5.2 weapons (with masteries), armor, and conditions, loaded from
  data at compile time and looked up by slug.
- A `Srd` module documenting a full combat round end to end.

## [0.1.0]

- Initial package scaffold. `Srd.Dice` placeholder module; no functionality
  yet.
