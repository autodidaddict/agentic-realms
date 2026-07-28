# Phase 1 Data Model: SRD 5e Character Stats

**Feature**: 020-srd-5e-stats | **Date**: 2026-07-28 | **Plan**: [plan.md](./plan.md)

## 1. What is persisted and what is derived

The dividing line is FR-006. A value is persisted only if it cannot be recomputed: the choices made at creation, and the two counters that change during play.

| Persisted | Derived on read |
|---|---|
| `species_slug`, `class_slug`, `background_slug` | species name, class name, background name, speed, hit die |
| `size` (Human offers Small or Medium) | — |
| `str`, `dex`, `con`, `int`, `wis`, `cha` | the six ability modifiers |
| `level`, `xp` | proficiency bonus, experience progress, hit dice |
| `hp`, `max_hp` | health fraction for the bar |
| `skill_proficiencies`, `save_proficiencies` | all eighteen skill modifiers, all six save modifiers, passive perception |
| `feat_slugs` | nothing this milestone; feats are recorded, not applied |
| — | armor class, initiative |

Size is persisted rather than derived because Human's `sizes` is `[:small, :medium]`, which the SRD treats as a player choice. Every other species trait is a lookup.

## 2. Read model: `player_state`

### 2.1 Migration

One read-model migration, `<ts>_add_srd_character_columns.exs`:

```elixir
alter table(:player_state) do
  add :species_slug,    :string
  add :class_slug,      :string
  add :background_slug, :string
  add :size,            :string
  add :skill_proficiencies, {:array, :string}, null: false, default: []
  add :save_proficiencies,  {:array, :string}, null: false, default: []
  add :feat_slugs,          {:array, :string}, null: false, default: []

  remove :mana
  remove :max_mana
end
```

The slug columns are nullable because a row can legally exist without a character — `PlayerSpawned` can arrive first on a replay. Nothing else needs a default, because the world is purged and restaged (research R8) and there are no pre-existing rows to keep valid. The empty-array defaults on the proficiency columns serve that same replay window, not history.

No event-store migration. The event log is destroyable at this stage, so `CharacterCreated` simply starts appearing in streams, and `mix world.reset` drops both databases before the first run.

`npc_clones` and `blueprints` are untouched (FR-034). Their `mana` / `max_mana` columns survive as unread state for the NPC stat-block feature to reshape.

### 2.2 Schema

`AgenticRealms.World.Schemas.PlayerState` gains the seven fields above and drops `mana` / `max_mana`.

Feature 019's field defaults (`str: 12` and the rest, `level: 1`, `hp: 10`) are **removed**. Every character now arrives complete via `CharacterCreated`, which the mount dispatches before `SpawnPlayer`, so a placeholder ability score is never correct and never read. Leaving them would mean a row could render a plausible-looking character that nobody created.

## 3. Write model

### 3.1 Command — `World.Commands.CreateCharacter`

```elixir
@enforce_keys [:player_id, :species_slug, :class_slug, :background_slug, :size,
               :abilities, :skill_proficiencies, :save_proficiencies,
               :feat_slugs, :max_hp]
defstruct [...]
```

`abilities` is `%{str: 17, dex: 13, con: 15, int: 12, wis: 10, cha: 8}`. Proficiency lists are strings on the wire (skill and ability atoms serialize badly and the read model stores strings anyway).

The command carries a fully-formed character. The aggregate does not generate, look up, or default anything — see research R4.

Routed to `Player` in `World.Router`, keyed by `player_id` like every other player command.

### 3.2 Event — `World.Events.CharacterCreated`

```elixir
@derive Jason.Encoder
@enforce_keys [:player_id, :species_slug, :class_slug, :background_slug, :size,
               :abilities, :skill_proficiencies, :save_proficiencies,
               :feat_slugs, :hp, :max_hp]
defstruct [..., version: 1]
```

Same shape as the command plus `hp` (equal to `max_hp` at creation, FR-013). `abilities` is a map with string keys after a JSON round trip, so `apply/2` reads it with `Map.fetch!/2` on strings via a small normalizer, the same treatment `discovered_room_ids` already gets.

### 3.3 Aggregate — `World.Player`

New struct fields: `species_slug`, `class_slug`, `background_slug`, `size`, `skill_proficiencies`, `save_proficiencies`, `feat_slugs`. Removed: `mana`, `max_mana`.

`execute/2` for `CreateCharacter` is idempotent on `species_slug`:

```elixir
def execute(%__MODULE__{species_slug: nil}, %CreateCharacter{} = cmd), do: %CharacterCreated{...}
def execute(%__MODULE__{}, %CreateCharacter{}), do: :ok
```

Every mount dispatches it; only the first emits. This is the `RecordRoomDiscovery` pattern.

`apply(%PlayerSpawned{})` stops seeding the six 12s, level, hp, and mana. It sets `id` and `current_room_id` only. Starting stats now arrive with `CharacterCreated`, which is the event that means "this character exists".

`execute/2` for `AwardXp` swaps `LevelCurve.level_for_xp/1` for `Srd.Rules.Experience.level_for_xp/1`. Everything else about the award path — the `applied_award_ids` MapSet, the non-positive no-op, the conditional `PlayerLeveledUp` — is unchanged. Because `level_for_xp/1` caps at 20, a level 20 character awarded more XP emits `PlayerXpAwarded` and no `PlayerLeveledUp`, which is FR-029 with no extra clause.

Maximum hitpoints do not rise on level-up in the aggregate. `max_hp` is stored, but it is recomputed from class, level, and Constitution by `Srd.Rules.Hitpoints.maximum/3` on read, so the stored value is only ever the creation value. See §5.3 for why that is the shape chosen.

### 3.4 Projector — `PlayerStateProjector`

New clause:

```elixir
def handle(%CharacterCreated{} = e, _meta) do
  Repo.insert!(%PlayerState{player_id: e.player_id, ...},
    on_conflict: [set: [species_slug: ..., str: ..., ...]],
    conflict_target: :player_id)
end
```

An upsert, matching the `PlayerSpawned` clause. `ensure_character/1` runs first at mount so this is normally the insert that creates the row, but neither clause may assume the other has run — a replay from position 0 can deliver them in either order.

All values are absolute and come from the event, so re-handling is idempotent (Principle II). The `on_conflict` set names only the character columns, so a redelivered `CharacterCreated` cannot reset `current_room_id`, `xp`, or `level`.

The `PlayerSpawned` clause is unchanged and keeps its `on_conflict: [set: [current_room_id: ...]]`, which already refuses to reset earned progression.

## 4. The SRD experience table

New module `Srd.Rules.Experience` in the package.

| Level | XP | Level | XP |
|---|---|---|---|
| 1 | 0 | 11 | 85,000 |
| 2 | 300 | 12 | 100,000 |
| 3 | 900 | 13 | 120,000 |
| 4 | 2,700 | 14 | 140,000 |
| 5 | 6,500 | 15 | 165,000 |
| 6 | 14,000 | 16 | 195,000 |
| 7 | 23,000 | 17 | 225,000 |
| 8 | 34,000 | 18 | 265,000 |
| 9 | 48,000 | 19 | 305,000 |
| 10 | 64,000 | 20 | 355,000 |

Function contracts are in [contracts/experience.md](./contracts/experience.md).

`AgenticRealms.World.LevelCurve` and its test are deleted.

## 5. Derivation

### 5.1 `Srd.Character.derive/1` — the derived layer, in the package

Every calculation behind the sheet lives in `srd_5e`. The game builds a facts map from `player_state`, calls `derive/1`, and renders the result. It does no SRD arithmetic itself.

Full input and output shapes are in [contracts/character-derivation.md](./contracts/character-derivation.md). What `derive/1` composes:

| Value | Source |
|---|---|
| ability modifier | `Srd.Rules.Ability.modifier/1` |
| proficiency bonus | `Srd.Rules.Proficiency.bonus/1` |
| skill modifier | `Srd.Rules.Skill.check_modifier/3` with `proficient?:` |
| saving throw modifier | `Srd.Rules.Save.modifier/3` **(new)** |
| passive perception | `Srd.Rules.Check.passive/2` over the perception modifier |
| armor class | `Srd.Rules.ArmorClass.compute/3`, with `nil` armor this milestone |
| initiative | `Srd.Rules.Initiative.modifier/1` **(new)** |
| maximum hitpoints | `Srd.Rules.Hitpoints.maximum/3` **(new)** |
| hit dice | `Srd.Rules.Hitpoints.hit_dice/2` **(new)** |
| speed, size, names | `Srd.Content.Species` / `Classes` / `Backgrounds` lookups by slug |
| experience progress | `Srd.Rules.Experience.progress/1` **(new)** |
| display names, ordering | `Srd.Rules.Ability.all/0`, `name/1`; `Srd.Rules.Skill.name/1` **(new)** |

There is no `AgenticRealms.World.Character`. An earlier draft had one; it held exactly this arithmetic and is dropped.

### 5.2 Ability priority

Generation needs "which ability matters most to this class", and it must be deterministic (FR-012). This is game policy, not an SRD rule — the SRD says a character assigns its scores, not how — so it lives in `World.CharacterGen`. One ordering serves every place generation needs a tiebreak:

1. the class's primary ability, taking the first when the SRD offers a choice (`{:any, [:str, :dex]}` → `:str`);
2. then its saving throw proficiencies, in the order the SRD lists them;
3. then the remaining abilities in canonical order STR, DEX, CON, INT, WIS, CHA.

For Fighter this is **STR, CON, DEX, INT, WIS, CHA**.

### 5.3 Maximum hitpoints

Derived, not accumulated, by `Srd.Rules.Hitpoints.maximum/3`:

```
max_hp = hit_die_max + (level - 1) × (hit_die_max / 2 + 1) + level × con_modifier
```

floored at 1. This is the SRD's fixed-value option — take the maximum at level 1, the average thereafter — and it is a pure function of class, level, and Constitution.

Deriving rather than accumulating means level-up needs no HP event and cannot drift. It also means the stored `max_hp` is redundant after creation. It stays on the row because current `hp` needs something to clamp against once damage exists, and because dropping it would churn a column the combat feature immediately wants back.

The whole formula is in the package (`starting/2`, `per_level/2`, `maximum/3`). The game never assembles it.

### 5.4 The sheet shape

`World.Stats.for_player/1` is a thin adapter: read the row, build the facts map, call `Srd.Character.derive/1`, and merge in the two things the package does not own — the player's name and current hitpoints. It returns:

```elixir
%{
  name: "Kevin",
  species: "Human", class: "Fighter", background: "Soldier",
  size: "Medium", speed: 30,
  level: 1, proficiency_bonus: 2,
  xp: %{total: 0, into_level: 0, to_next: 300, fraction: 0.0, maxed?: false},
  hp: %{cur: 12, max: 12},
  hit_dice: "1d10",
  armor_class: 11, initiative: 1, passive_perception: 12,
  abilities: [%{key: :str, name: "Strength", score: 17, modifier: 3}, ...],   # 6, STR..CHA
  saves:     [%{key: :str, name: "Strength", modifier: 5, proficient?: true}, ...],  # 6
  skills:    [%{key: :acrobatics, name: "Acrobatics", ability: :dex,
                modifier: 3, proficient?: true}, ...]                          # 18, alphabetical
}
```

`health_tier/2` and `relative_power/2` stay on `Stats` unchanged. Examine reads `level` and `hp`/`max_hp` from `npc_clones` exactly as it does today (FR-035).

## 6. Generation

`World.CharacterGen.default/1` is pure: given the config, it returns the command payload. No repo access, no randomness.

Generation stays in the game because it is policy, not rules. The SRD says a fighter picks two skills from a list; it does not say which two. The package supplies the raw material — `Srd.Rules.Ability.standard_array/0`, `Srd.Content.Background.spreads/0`, each class's `skill_choice` — and `CharacterGen` decides among it.

### 6.1 Configuration

`config/config.exs`, the single place FR-010 requires:

```elixir
config :agenticrealms, :character_defaults,
  species: "human",
  class: "fighter",
  background: "soldier",
  size: :medium,
  species_skill: :perception,
  species_feat: "alert"
```

`species_skill` fills Human's *Skillful* trait and `species_feat` its *Versatile* trait, both of which the SRD leaves to the player. Perception is the most broadly useful skill in play; Alert is the one origin feat with no sub-choice of its own, and Soldier has already taken Savage Attacker.

### 6.2 Steps

1. **Ability scores.** Deal the standard array `[15, 14, 13, 12, 10, 8]` down the §5.2 priority.
2. **Background increases.** Apply the SRD `[2, 1]` spread over the background's three abilities, `+2` to the highest-priority and `+1` to the next.
3. **Skills**, in this order so nothing is wasted on a duplicate:
   - the background's two;
   - the species skill from config;
   - the class's `skill_choice.choose` picks from its list, excluding the already-proficient, ranked by the character's modifier in each skill's governing ability, descending, tie-broken alphabetically.
4. **Saving throws.** The class's two.
5. **Feats.** The background's origin feat plus the configured species feat. Recorded only.
6. **Hitpoints.** §5.3 at level 1.

### 6.3 The default character

Human Fighter with a Soldier background, level 1:

| | STR | DEX | CON | INT | WIS | CHA |
|---|---|---|---|---|---|---|
| Score | 17 | 13 | 15 | 12 | 10 | 8 |
| Modifier | +3 | +1 | +2 | +1 | +0 | −1 |
| Save | **+5** | +1 | **+4** | +1 | +0 | −1 |

Derived: level 1, 0 XP (300 to level 2), HP 12/12, hit dice 1d10, AC 11, initiative +1, proficiency bonus +2, speed 30, Medium, passive perception 12.

Proficient skills: Acrobatics +3, Athletics +5, History +3, Intimidation +1, Perception +2.
Feats recorded: `savage-attacker` (Soldier), `alert` (Human).

Scores reach 17/13/15 because the standard array lands STR 15 / CON 14 / DEX 13 and Soldier's `[2, 1]` adds +2 STR and +1 CON.

## 7. Seed

`Seed.orchard_quest` reward changes from `"xp" => 100` to `"xp" => 300`, the SRD level 2 threshold, preserving feature 019's intent that the first quest is worth exactly one level (FR-031).

## 8. Entity relationships

```text
Accounts.Player ──1:1── World.Player (aggregate)
                              │  CharacterCreated, PlayerXpAwarded, PlayerLeveledUp
                              ▼
                         player_state (read model)
                              │  slugs + scores + level/xp + proficiency sets
                              ▼
              World.Stats.for_player/1 (adapter)
                              │  facts map
                              ▼
                  Srd.Character.derive/1  ──composes──▶ Srd.Rules.*
                              │                         Srd.Content.*
                              ▼
                       GameLive :stats ──▶ sheet + sidebar
```

`npc_clones` sits outside this entirely and is unchanged.
