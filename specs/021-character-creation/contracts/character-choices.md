# Contract: `Srd.Character.choices/1` and `grants/1`

**Feature**: 021-character-creation | **Package**: `packages/srd_5e`

Two pure functions added to `Srd.Character`, beside the `derive/1` feature 020 put there. They
answer the two questions a character builder asks before a character exists: what is still open,
and what came for free.

Both take selections and return options. Neither holds a character, a partial build, or any state,
so ADR-0004's line is unchanged and no amendment is needed. `choices/1` is the ADR's own stated
purpose — "the same question in all four places, and it is the question a character builder asks
over and over" — answered once across all five content types instead of field by field.

---

## `choices/1`

```elixir
@spec choices(selections()) :: [open_choice()]

@type selections :: %{
        optional(:species) => String.t() | nil,
        optional(:class) => String.t() | nil,
        optional(:background) => String.t() | nil,
        optional(:level) => pos_integer()      # defaults to 1
      }

@type open_choice :: %{
        key: choice_key(),
        source: :species | :class | :background,
        label: String.t(),
        text: String.t() | nil,
        choice: Srd.Content.Choice.t()
      }

@type choice_key ::
        :species_size
        | :species_lineage
        | :class_skills
        | :class_tool
        | :background_tool
        | {:feature, String.t()}
```

Returns every pick-N-of-M decision the given selections leave open at that level, in a stable
order: species choices, then class, then background, and within each source in the order the
content lists them. A caller renders the list as given.

**A partial selection returns a partial answer.** `choices(%{species: "elf"})` returns the elf's
choices and nothing else, so the dialog can ask a species' questions before a class is picked.
`choices(%{})` returns `[]`.

**Settled choices are omitted.** A choice whose options number no more than its picks is already
decided, so it does not come back — this is `Srd.Content.Choice.fixed?/1`, which already exists.
That is what makes a dwarf return no lineage question and a single-size species return no size
question, with no special case for either.

**Deferred choices are omitted.** Only choices available at or below `level` are returned, so a
level 1 call never asks for a subclass. Callers that want to *say* when a deferred choice arrives
read `class.subclass_level` directly; `choices/1` reports what is open, not what is coming.

### What each key covers

| Key | Source | Comes from | Which content offers it |
|---|---|---|---|
| `:species_size` | species | `species.sizes` when it holds more than one | human, tiefling |
| `:species_lineage` | species | `species.lineages` when non-empty; `label` is `species.lineage_trait` | dragonborn, elf, gnome, goliath, tiefling |
| `:class_skills` | class | `class.skill_choice` | all twelve |
| `:class_tool` | class | `class.tool_proficiency` when present and not fixed | bard, monk (druid's and rogue's are fixed) |
| `:background_tool` | background | `background.tool` when not fixed | soldier only |
| `{:feature, name}` | species or class | any `Feature` at or below `level` whose `:choice` is set and not fixed | elf, human; barbarian, cleric, druid, fighter, paladin, ranger, rogue at level 1 |

`{:feature, name}` is what carries a fighter's Fighting Style and Weapon Mastery, a cleric's Divine
Order, and a human's Skillful and Versatile, without any of them being named in code. A feature
choice that a future content addition introduces arrives through the same key with no change here
and no change in the game.

### Examples

```elixir
iex> Srd.Character.choices(%{species: "dwarf", class: "wizard", background: "sage"})
[
  %{key: :class_skills, source: :class, label: "Skill Proficiencies", ...},
  %{key: {:feature, "Epic Boon"}, ...}   # only at level 19+; absent at level 1
]

iex> Srd.Character.choices(%{species: "elf"}) |> Enum.map(& &1.key)
[:species_lineage, {:feature, "Keen Senses"}]

iex> Srd.Character.choices(%{species: "human"}) |> Enum.map(& &1.key)
[:species_size, {:feature, "Skillful"}, {:feature, "Versatile"}]

iex> Srd.Character.choices(%{class: "fighter"}) |> Enum.map(& &1.key)
[:class_skills, {:feature, "Fighting Style"}, {:feature, "Weapon Mastery"}]
```

### Raises

`ArgumentError` for a slug no content matches, matching `derive/1`.

---

## `grants/1`

```elixir
@spec grants(selections()) :: %{
        skills: [Srd.Rules.Skill.skill()],
        saves: [Srd.Rules.Ability.t()],
        feats: [String.t()],
        tools: [String.t()],
        features: [Srd.Content.Feature.t()]
      }
```

What the selections grant outright, with nothing to choose. Every list is deduplicated and sorted,
so a feat granted by both a background and a species appears once — which is what FR-024 requires
and what the spec's "a background's origin feat and a human's Versatile pick are the same feat"
edge case turns on.

| Field | Comes from |
|---|---|
| `skills` | `background.skills`, plus any species or class feature whose choice is fixed |
| `saves` | `class.saving_throws` |
| `feats` | `background.origin_feat` |
| `tools` | `class.tool_proficiency` and `background.tool` when fixed — a druid's herbalism kit, a rogue's thieves' tools, an acolyte's calligrapher's supplies |
| `features` | every `Feature` at or below `level` from species and class, plus the features of every granted feat |

A fixed choice is a grant, which is the other half of `choices/1` omitting it: between them, every
decision the content carries is either answered or asked, and none is dropped. `tools` is not in
`Srd.Character.derive/1`'s facts and nothing mechanical consumes it yet; it is here because leaving
a real grant out would make the function's name a lie, and the review renders it.

**Which abilities a background may raise is deliberately not here.** It was, briefly. It is not
granted — it is the set an increase may be spent on — and putting it in a map called `grants` made
the name inaccurate to serve one consumer's ability step. `Srd.Content.Backgrounds.get(slug)
.ability_scores` already answers it, and feature 021's `CharacterDraft.raisable_abilities/1` reads
it there, which is where a question the creation flow asks belongs.

`features` drives the review's "what you will have" list and the detail FR-017 requires on each
option.

---

## `Srd.Content.Choice` gains `:size`

```elixir
@kinds ~w(ability equipment feat feature lineage size skill tool weapon)a
```

One word. A species' size choice is a pick-one-of-a-list like every other, and giving it the same
shape is what lets the dialog render every open choice with one component instead of special-casing
the one that is a bare list today. `species.sizes` is unchanged; `choices/1` wraps it.

---

## Testing

All pure, all `async: true`, all DB-free.

- `choices/1` over all nine species, twelve classes, and four backgrounds. Every returned choice's
  `from` is non-empty and every option resolves to real content.
- The four species with no lineage (dwarf, halfling, human, orc) return no `:species_lineage`.
- Human and tiefling return `:species_size`; the seven single-size species do not.
- Fighter at level 1 returns Fighting Style and Weapon Mastery; at level 19 it also returns Epic
  Boon; at no level does it return a subclass.
- A settled choice is absent: acolyte's tool, druid's and rogue's tool proficiency, all of which
  `Choice.fixed?/1` already reports as fixed. Soldier's tool, which is a choice of four, is present.
- `grants/1` deduplicates a feat granted twice, and its `skills` and `feats` are sorted.
- `grants/1` reports the fixed tools `choices/1` omits, so nothing the content carries is dropped
  between them.
- `grants/1` has no `:abilities` key — which abilities a background may raise is read from the
  background itself.
- Partial selections: species only, class only, and `%{}`.
