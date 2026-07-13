# Contract: Domain Commands & Events (Real Stats)

The write-side contract. Player stats change **only** through these, dispatched to the `World.Player` aggregate (sole writer). NPC stats are not event-sourced this milestone (frozen at spawn — see `stat-defaults.md`).

## Command: `AwardXp` → `World.Player`

| Field | Type | Rules |
|---|---|---|
| `player_id` | binary_id | routes to `player-<id>` stream |
| `amount` | integer | MUST be > 0 to have effect; ≤ 0 is a no-op |
| `award_id` | string | idempotency key; deterministic per source (e.g. `"quest:" <> quest_id`) |
| `source` | term | provenance for logs/telemetry (e.g. `{:quest, quest_id}`) |

Dispatched from `Commands.award_xp/3` with `consistency: :strong`. Added to the `dispatch([...], to: Player)` list in `router.ex`.

### Execution semantics

- **Idempotent / no-op**: if `amount ≤ 0` **or** `award_id ∈ applied_award_ids` → return `:ok`, emit **no events**.
- **Otherwise**: `new_total = xp + amount`; `new_level = LevelCurve.level_for_xp(new_total)`.
  - Always emit `%PlayerXpAwarded{}`.
  - Emit `%PlayerLeveledUp{}` **iff** `new_level > level` (single event even across a multi-level jump; `to_level` is the final level).

## Event: `PlayerXpAwarded`

```
%PlayerXpAwarded{player_id, amount, new_total, award_id, version: 1}   @derive Jason.Encoder
```
`apply/2`: `xp := new_total`; `applied_award_ids := MapSet.put(applied_award_ids, award_id)`.
Projected by `PlayerStateProjector` → `player_state.xp := new_total` (update by PK, idempotent).

## Event: `PlayerLeveledUp`

```
%PlayerLeveledUp{player_id, from_level, to_level, version: 1}   @derive Jason.Encoder
```
`apply/2`: `level := to_level` — and **nothing else** (FR-011a: no stat growth).
Projected by `PlayerStateProjector` → `player_state.level := to_level`.

## Event change: `QuestCompleted` gains `xp`

```
%QuestCompleted{quest_id, player_id, completed_at, xp \\ 0, version: 1}
```
`xp` is the denormalized reward XP, threaded `finalize_quest/2 → FinalizeQuest.reward_xp → QuestCompleted.xp`. Absent/legacy quests default to 0.

## Reaction: `World.Progression.XpAwarder` (named `Commanded.Event.Handler`, `:eventual`)

```
handle(%QuestCompleted{player_id, quest_id, xp}) when xp > 0 -> Commands.award_xp(player_id, xp, "quest:"<>quest_id); :ok
handle(%QuestCompleted{}) -> :ok
```

**Cluster contract**: a *named* handler is an exclusive single cluster-wide subscriber → exactly one node awards each quest's XP (Principle I). At-least-once redelivery is tolerated because the aggregate dedupes on `award_id`.

## Invariants

- No command/route awards XP to an NPC (FR-003, FR-012).
- Re-running the Player stream from position 0 reproduces identical `xp`/`level` (award-id guard + deterministic curve) — replay-safe (Principle II).
- `PlayerLeveledUp` never alters HP/mana/abilities (FR-011a).
