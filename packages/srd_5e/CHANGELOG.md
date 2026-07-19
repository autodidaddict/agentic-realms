# Changelog

The format is based on Keep a Changelog, and this project follows Semantic
Versioning.

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
