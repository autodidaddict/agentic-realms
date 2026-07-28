# 4. Expose SRD Character-Creation Content

- **Status**: Accepted
- **Date**: 2026-07-27
- **Deciders**: Kevin Hoffman
- **Related**: ADR-0002 (roll our own resolution; breadth lives in authored data
  on top of the engine), ADR-0003 (SRD 5.2 is the baseline, 5.1 only as per-rule
  opt-ins); feature 019 (real stats); the `srd_5e` package.

## Context

`srd_5e` exposes the content combat needs: weapons, armor, and conditions. A
consumer can resolve an attack against an AC, but it cannot make a character,
because nothing in the package says what a character may be. Feature 019 gave
players and NPCs ability scores, a level, and hit points, and nobody picked a
class, a species, or a background, because there was nothing to pick from.

What SRD 5.2 holds for character creation is a good deal smaller than the 2024
Player's Handbook, and stating it exactly matters, because the inventory is the
scope of the work:

- Twelve classes, each with exactly one subclass, chosen at level 3: Barbarian
  (Path of the Berserker), Bard (College of Lore), Cleric (Life Domain), Druid
  (Circle of the Land), Fighter (Champion), Monk (Warrior of the Open Hand),
  Paladin (Oath of Devotion), Ranger (Hunter), Rogue (Thief), Sorcerer (Draconic
  Sorcery), Warlock (Fiend Patron), Wizard (Evoker).
- Nine species: Dragonborn, Dwarf, Elf, Gnome, Goliath, Halfling, Human, Orc,
  Tiefling.
- Four backgrounds: Acolyte, Criminal, Sage, Soldier.
- Seventeen feats across four categories: four origin, two general, four
  fighting style, seven epic boon.

Two things in that inventory shape the design.

The 2024 rules have no races and no subraces. They have species, and where a
species offers a further choice, that choice is a trait of the species rather
than a uniform second tier. Elves choose an Elven Lineage (Drow, High Elf, Wood
Elf), gnomes a Gnomish Lineage (Forest, Rock), tieflings a Fiendish Legacy
(Abyssal, Chthonic, Infernal), dragonborn a Draconic Ancestry (ten dragon
types), goliaths a Giant Ancestry (six boons). Dwarves, halflings, humans, and
orcs offer nothing at that tier. A `Subrace` type would be ours rather than the
SRD's, and we would then be inventing an empty one for four of the nine species.

And nearly all of this content is choices. A class offers two skills from a
list and one of two starting equipment bundles; a background fixes an origin
feat and a pair of skills; a species may offer a lineage; a fighter picks a
fighting style feat. "What may be chosen here" is the same question in all four
places, and it is the question a character builder asks over and over. That is
the API this ADR is really about.

## Decision

Expose classes, subclasses, species, backgrounds, and feats as `Srd.Content`
data, loaded at compile time like the existing content, with a filtering surface
that answers what may be chosen and holds nothing about what was chosen.

### Content types

New modules follow the existing struct-plus-collection split, where the struct
carries the record and the plural module owns loading and lookup:

- `Srd.Content.Class` / `Classes`
- `Srd.Content.Subclass` / `Subclasses`
- `Srd.Content.Background` / `Backgrounds`
- `Srd.Content.Feat` / `Feats`
- `Srd.Content.Item` / `Items`, covering the packs, tools, and adventuring gear
  that starting equipment refers to, so every equipment entry resolves to a slug
  instead of a loose string.

Two more structs carry pieces the others hold rather than being looked up on
their own: `Srd.Content.Bundle` is one starting equipment option, and
`Srd.Content.Lineage` is one option within a species trait.

`Srd.Content.Species` is the one exception: its plural is the same word, so the
struct and its `all/0`, `get/1`, `fetch!/1` live in a single module rather than
inventing a name for the collection. Elixir will not let a module build its own
struct while compiling, so the compile-time data sits in a `@moduledoc false`
`Srd.Content.Species.Data` behind it. Callers only ever see `Species`.

Species is the whole of the sub-tier. A species carries its options inline as
`%Species{lineages: [...]}`, each named after the SRD's own trait — Elven
Lineage, Gnomish Lineage, Fiendish Legacy, Draconic Ancestry, Giant Ancestry —
and the list is simply empty for dwarves, halflings, humans, and orcs. There is
no `Subrace` type, no `Race` alias, and no synthetic tier standing in for the
species that do not have one. Callers that want to know whether a species asks
for a further choice check whether `lineages` is empty, the same way they would
check any other `Choice`.

A background carries every effect the 2024 rules put on it, because creation
does not work without them:

- the three ability scores it can raise, and the spread the player picks between
  (+2 and +1, or +1 to all three)
- the origin feat it grants, by feat slug, with any option the background fixes
- its two skill proficiencies, as `Srd.Rules.Skill` atoms
- its tool proficiency
- its starting equipment, as a `Choice` between a bundle of item slugs plus
  gold, and a flat 50 GP

So Acolyte grants Magic Initiate (Cleric), Insight and Religion, and
calligrapher's supplies; Criminal grants Alert, Sleight of Hand and Stealth, and
thieves' tools; Sage grants Magic Initiate (Wizard); Soldier grants Savage
Attacker, Athletics and Intimidation, and a gaming set of the player's choice.

Two shared structs carry the shapes that recur everywhere:

- `Srd.Content.Choice` is one decision point: `kind`, how many to `choose`, and
  the list to choose `from`. Skill choices, lineage, equipment bundles, and
  fighting style are all `Choice`s, so a builder walks a uniform structure
  instead of learning five field names.
- `Srd.Content.Feature` is one granted feature: the `level` it arrives at, its
  `name`, restated `text`, and an optional `Choice`. Classes, subclasses,
  species, backgrounds, and feats all grant features, and all use this.

Feature text is a concise, accurate restatement of the mechanics, not verbatim
SRD prose. That is the rule the conditions data already follows, and it holds
here for the same reasons: it keeps the data files a workable size and the
package is a rules engine, not a reprint.

### Filtering

Each collection keeps `all/0`, `get/1`, and `fetch!/1`, and adds `all/1` taking
filter options that name fields, plus the relation-specific filters that the
cross-references make possible:

```elixir
Subclasses.for_class("fighter")     #=> [%Subclass{slug: "champion", ...}]
Feats.all(category: :origin)        #=> the four origin feats
Backgrounds.get("soldier").origin_feat        #=> "savage-attacker"
Classes.get("wizard").skill_choice             #=> %Choice{choose: 2, from: [...]}
Species.get("elf").lineages                    #=> [%Lineage{slug: "drow"}, ...]
Classes.multiclass_options(%{str: 15, wis: 13}) #=> classes whose primary ability qualifies
Feats.eligible(level: 4, abilities: %{str: 15}, features: [:fighting_style])
```

Feats are the only content whose availability depends on the character, so their
prerequisites are stored in machine-readable form (`{:level, 4}`,
`{:ability, [:str, :dex], 13}`, `{:feature, :fighting_style}`) alongside the
printed text. `Feats.eligible/1` is a pure predicate over facts the caller
passes in. Multiclass options need no new data at all: the SRD's rule is a 13 in
the primary ability of both classes, and `Class.primary_ability` already carries
it.

The library answers what may be chosen, never what has been chosen. It takes
facts as arguments and returns options; it holds no character, no partial build,
and no validation state machine. A consumer that wants different eligibility
rules reads the same prerequisite data and writes its own predicate.

### Data and cross-references

Content lives in `priv/data/*.exs` and is evaluated at compile time, one file
per type, the same as weapons and armor. Cross-references are by slug and are
validated while compiling, so a bad reference is a build failure rather than a
runtime `nil`: a subclass's class must exist, a background's origin feat must
exist, class and background skill lists must be `Srd.Rules.Skill` atoms, and
equipment entries must name real weapon, armor, or item slugs.

Options that are "any weapon", "any gaming set", or "a Fighting Style feat" are
written in the data as `{:weapons, filters}`, `{:items, category}`, and
`{:feats, category}`, and expand to real slugs while compiling. That keeps the
lists in one place and means a `Choice` always hands the caller slugs that
resolve. It also gives the collections a filter surface worth having on its own,
so `Weapons.all/1` and `Armors.all/1` gained the same field filters as the new
content.

Those references make compile-time dependencies between the collections, so the
graph stays acyclic and one-directional: `Choice` expands against weapons,
armor, items, and feats; backgrounds and classes depend on those; and subclasses
depend on classes. Nothing points back the other way.

### What this does not cover

Spells are out, and not merely deferred. They are the largest single chunk of
the SRD by a wide margin, and carrying several hundred of them would dwarf
everything decided here while most consumers of the creation content never touch
them. The likely home is a separate optional package that depends on this one,
so `srd_5e` stays the engine plus the content a character is built from, and a
consumer that needs the catalog opts into the weight.

That boundary is visible in two places. A caster is describable but not
complete: the class data says how many spells a level 3 wizard prepares, not
which ones. And two of the four backgrounds grant Magic Initiate, so the
background carries the feat and the spell list it names without being able to
resolve what is on that list.

Magic items, monsters, and ability score generation are also out. Score
generation in particular stays with the consumer, which already generates stats
in feature 019 and may not use the SRD's method at all.

Content is SRD 5.2 only, per ADR-0003. There is no 5.1 race and subrace set, and
adding one is not a per-rule `edition:` opt-in but a second content set, which
that ADR already put out of scope.

Homebrew is out of scope too. Everything here is plain structs and plain lists,
so a consumer can assemble its own classes beside ours without the package
growing a registry or a runtime content-loading path.

## Consequences

**Positive**

- A consumer can present legal choices without reimplementing the SRD's tables,
  which is the gap that stops a character builder from existing today.
- Filtering is data-shaped, so the library never needs to know what a character
  is, and stays pure functions over compile-time data with no runtime
  dependency and DB-free tests (Principle IV, ADR-0002).
- `Choice` and `Feature` mean a builder learns two shapes and walks all five
  content types, rather than special-casing each.
- Compile-time cross-reference checking turns a mistyped slug into a build
  failure, which matters when the data is this much larger than what we have.
- Species and lineage match the rules we actually implement, so nothing has to
  be translated between the SRD's vocabulary and ours.

**Costs**

- This is far more data than weapons and armor. Twelve classes across twenty
  levels is the bulk of it, it is transcription with real error surface, and it
  needs per-class tests checking granted features against the printed table.
- Compile time grows, because all of it is evaluated while compiling.
- Restated feature text has to stay accurate as errata land, and correctness
  there is on us rather than on a citation.
- The package's public surface roughly doubles before 1.0, so more of it is
  exposed to the churn the README already warns about.
- Casters stay incomplete without the spell package, and that gap is visible to
  anyone building a wizard or reading a Magic Initiate grant.
- Splitting spells into an optional package means a versioning seam between the
  two, and it has to stay a one-way dependency.

## Alternatives considered

- **Model race and subrace to match SRD 5.1 and third-party tooling.** Rejected:
  5.2 is the baseline, subraces do not exist in it, and four of nine species
  would carry an empty tier we invented.
- **Ship a character builder — an `Srd.Character` that holds choices and
  validates a finished build.** Rejected: the consumer owns the character, and
  in this project that means aggregates and read models, not a struct in a rules
  library. Options in, state out stays the boundary.
- **Nest subclasses inside their class instead of indexing them.** Rejected: a
  saved character stores a subclass slug, and resolving it would mean walking
  every class to find it. `for_class/1` gives the filter without giving up the
  lookup.
- **One generic content entry with a `kind` tag.** Rejected: the fields that
  differ between a class and a feat are exactly the fields worth filtering on,
  and a generic entry throws away both the types and the filters.
- **Carry verbatim SRD prose for every feature.** Rejected: it does not help a
  builder pick anything, it multiplies the data, and it departs from the
  restatement rule the conditions data already set.
- **Load content at runtime from a JSON dataset.** Rejected: compile-time
  evaluation already works, validates cross-references at build, and keeps every
  lookup a map read.
- **Ship spells here too, so character creation is complete in one package.**
  Rejected: the spell catalog is larger than everything in this ADR combined, and
  every consumer would compile and carry it whether or not it casts. An optional
  companion package keeps the cost with the consumers who want it.

## Amendment: the derived layer (2026-07-28, feature 020)

The package now owns the calculations behind a character sheet, not only the
content that feeds them. `Srd.Character.derive/1` takes a character's facts —
species, class, background, level, ability scores, proficiencies — and returns
what follows: modifiers, proficiency bonus, saving throws, skills, passive
perception, armor class, initiative, hit point maximum, hit dice, and progress
toward the next level. `Srd.Rules.Experience` carries the advancement table
alongside it.

The line this ADR drew is unchanged, and the amendment exists because the module
name says otherwise at a glance. What was rejected above was a character builder
that *holds choices and validates a finished build*. `derive/1` holds nothing,
validates nothing, and constructs no struct. Facts in, numbers out, with the
consumer still owning the character in its aggregates and read models. It is the
same shape as `Srd.Content`'s "you pass in what you know and get back the
options", applied to arithmetic instead of options.

The reason to put it here rather than in the consumer is that the alternative
splits one set of rules across two repositories. `Save.modifier/3` in the library
while the saving-throw row is assembled in the game is an arbitrary boundary,
and the half left behind is the half no other consumer can reuse.

What the consumer still owns: persistence, and the *choices* a character makes.
The SRD says a fighter picks two skills from a list; it does not say which two.
Picking is the game's business, and the package supplies only the raw material —
`Ability.standard_array/0`, `Background.spreads/0`, and each class's
`skill_choice`.
