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

The derived layer: what follows from a character's choices, once they are made.
Content says what may be chosen and this says what the choices come to, so a
consumer never reimplements the arithmetic behind a character sheet.

- `Srd.Character.derive/1` takes a character's facts and returns the sheet:
  modifiers, proficiency bonus, saving throws, all eighteen skills, passive
  perception, armor class, initiative, hit point maximum, hit dice, and progress
  toward the next level. It holds no character, exactly as the content layer
  holds none — a map in, a map out.
- `Srd.Rules.Experience` carries the twenty-level table and the calculations
  over it: `threshold/1`, `level_for_xp/1`, and `progress/1`, which reports the
  absence of a next level at the cap rather than inventing one.
- `Srd.Rules.Hitpoints` sizes the pool as well as tracking it: `starting/2`,
  `per_level/2`, `maximum/3`, and `hit_dice/2`.
- Smaller additions the sheet needed: `Ability.all/0`, `Ability.name/1`,
  `Ability.standard_array/0`, `Skill.name/1`, `Save.modifier/3`, and
  `Initiative.modifier/1`.

What a character still has to decide, which is what a builder asks before a
character exists. The counterpart to `derive/1`: one says what follows from the
choices, this says which choices are still open.

- `Srd.Character.choices/1` takes a species, class, and background and returns
  every pick-N-of-M decision they leave open at a level, each tagged with a
  stable key, its source, its label, and the `Choice` itself. Settled choices
  and choices the SRD defers to a higher level are omitted, so a dwarf returns
  no lineage question and a level 1 character is never asked for a subclass.
- `Srd.Character.grants/1` returns what those three grant outright — skills,
  saving throws, feats, tool proficiencies, and the features in force at a
  level, a granted feat's own features included — deduplicated, so a feat
  granted twice appears once. Which abilities a background may raise is
  deliberately not among them: that is the set an increase may be spent on
  rather than something granted, and the background already carries it.
- A choice with no more options than picks is settled rather than open, so
  `choices/1` omits it and `grants/1` reports it. Between them every decision
  the content carries is either answered or asked, and none is dropped.
- `Srd.Content.Choice` gains a `:size` kind, so a species that may be more than
  one size offers that as a choice like any other.

Both take selections and return options. Neither holds a character, a partial
build, or any state, so the line ADR-0004 drew is unchanged.

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
