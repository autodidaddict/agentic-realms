# Contract: Command, Event, and Aggregate Changes

**Feature**: 020-srd-5e-stats (FR-001 through FR-005, FR-008 through FR-014, FR-027 through FR-029)

## `CreateCharacter` → `CharacterCreated`

### Command

`AgenticRealms.World.Commands.CreateCharacter`

| Field | Type | Notes |
|---|---|---|
| `player_id` | integer | routing key |
| `species_slug` | string | `"human"` |
| `class_slug` | string | `"fighter"` |
| `background_slug` | string | `"soldier"` |
| `size` | string | `"medium"` |
| `abilities` | map | `%{str: .., dex: .., con: .., int: .., wis: .., cha: ..}` |
| `skill_proficiencies` | [string] | sorted, no duplicates |
| `save_proficiencies` | [string] | the class's two |
| `feat_slugs` | [string] | recorded, not applied |
| `max_hp` | integer | ≥ 1 |

Routed to `World.Player` in `World.Router`, identified by `player_id`.

Facade: `World.Commands.ensure_character/1`, dispatching at `consistency: :strong`. It builds the payload from `World.CharacterGen.default/1` and returns `{:ok, :created}` or `{:ok, :already_created}`. Never returns an error for an already-created character — the aggregate treats that as a no-op, not a fault.

### Event

`AgenticRealms.World.Events.CharacterCreated` — every command field, plus `hp` (equal to `max_hp`, FR-013) and `version: 1`. `@derive Jason.Encoder`.

`abilities` comes back from JSON with string keys. `apply/2` normalizes them, the same way `discovered_room_ids` is normalized from a list back into a MapSet.

### Aggregate behavior

| Given | Command | Result |
|---|---|---|
| `species_slug: nil` | `CreateCharacter` | `%CharacterCreated{}` |
| `species_slug: "human"` | `CreateCharacter` | `:ok`, no event |

Idempotent by construction, so the every-mount dispatch that backfills pre-existing characters (FR-027) costs one aggregate call and nothing else.

`apply(%CharacterCreated{})` sets the slugs, size, the six scores, `hp`, `max_hp`, and both proficiency lists.

## Changes to existing events

### `PlayerSpawned`

Shape unchanged. `apply/2` no longer seeds stats — it sets `id` and `current_room_id` only. Starting stats belong to `CharacterCreated`.

The projector clause keeps its `on_conflict: [set: [current_room_id: ...]]`, which already refuses to reset earned progression on a replay.

### `AwardXp` / `PlayerXpAwarded` / `PlayerLeveledUp`

Shapes unchanged. The only edit is inside `execute/2`:

```diff
- alias AgenticRealms.World.LevelCurve
+ alias Srd.Rules.Experience
...
- new_level = LevelCurve.level_for_xp(new_total)
+ new_level = Experience.level_for_xp(new_total)
```

FR-029 falls out of the cap rather than needing a clause: at level 20, `level_for_xp/1` returns 20 for any total, so `new_level > current_level` is false and only `PlayerXpAwarded` is emitted. The XP is still recorded.

Idempotency is untouched. `applied_award_ids` still guards redelivery (FR-026).

## Removals

| Removed | Where |
|---|---|
| `AgenticRealms.World.LevelCurve` | module and its test, replaced by `Srd.Rules.Experience` |
| `mana`, `max_mana` | `Player` aggregate struct, `PlayerState` schema, `player_state` table |
| stat seeding in `apply(%PlayerSpawned{})` | `Player` aggregate |
| `GameData.player_stats/0`, `GameData.ability_scores/0` | if still present after feature 019 |

`npc_clones` and `blueprints` keep every column they have, including mana (FR-034).

## Ordering at mount

```elixir
{:ok, _} = Commands.ensure_character(player_id)             # new, :strong
:ok = Commands.spawn(player_id, Seed.starting_room_id())   # existing, :strong
stats = Stats.for_player(player_id)                         # sees both
```

Creation first, so the `player_state` row is born with a complete character rather than existing briefly with placeholder scores. `Queries.current_room_of/1` returns `{:error, :no_current_room}` for a row whose `current_room_id` is `NULL` exactly as it does for a missing row, so `spawn/2` still dispatches correctly against the row `CharacterCreated` just made.

Both are strongly consistent, so the read below them cannot race the projector.

Both projector clauses upsert, so neither depends on the other having run first — the order is for cleanliness, not correctness. A test asserts a character exists with real scores before `PlayerSpawned` is handled.

## Cluster semantics (Principle I)

Nothing new is introduced. `CreateCharacter` is a per-player-stream command dispatched from the player's own LiveView, exactly like `SpawnPlayer`. Two nodes racing to create the same character is safe: the aggregate is a single writer per stream, so the second dispatch finds `species_slug` set and emits nothing. `XpAwarder` is unchanged and remains the only cross-aggregate reaction. No new Horde registry, no new singleton, no new stateful process.
