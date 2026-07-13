# Phase 1 Data Model: Real Stats — Players & NPCs

Derived from the spec's Key Entities + Functional Requirements and the Phase 0 decisions. Covers the write-side (commands/events/aggregate state), the read-side (columns + migration), and the pure computation modules.

---

## 1. Stat set (shared vocabulary)

Every player and NPC carries:

| Field | Type | Players | NPCs | Notes |
|---|---|---|---|---|
| `str,dex,con,int,wis,cha` | integer | ✅ | ✅ | Ability scores. Default **12**. Display-only this milestone (FR-004). |
| `level` | integer | ✅ | ✅ | Default **1**. Players: derived from XP at award time. NPCs: authored, never derived (FR-010). |
| `xp` | integer | ✅ | ❌ | Default **0**. Players only (FR-003). |
| `hp` / `max_hp` | integer | ✅ | ✅ | Current / maximum hitpoints. Default **10 / 10** for players; NPC `max_hp` from blueprint, `hp` initialized to `max_hp` at spawn. |
| `mana` / `max_mana` | integer | ✅ | ✅ | Current / maximum mana. Default **10 / 10** for players; NPC `max_mana` from blueprint, `mana` initialized to `max_mana` at spawn. |

Ability **modifier** = `floor((score − 10) / 2)` — derived at display time, not stored.

---

## 2. Write side — Player aggregate (`World.Player`)

### 2.1 Aggregate state additions (`player.ex` defstruct)

Add: `str, dex, con, int, wis, cha` (default 12), `level` (1), `xp` (0), `hp`, `max_hp`, `mana`, `max_mana` (10), and `applied_award_ids: MapSet.new()` (idempotency guard).

`applied_award_ids` is a `MapSet`, so it needs the same snapshot treatment as `discovered_room_ids`: extend the existing `Jason.Encoder` impl (render as list) and `Commanded.Serialization.JsonDecoder` impl (rebuild MapSet) at the bottom of `player.ex`.

### 2.2 `apply(%PlayerSpawned{})` seeds defaults

`PlayerSpawned` is **unchanged** (still `[:player_id, :room_id]`). Defaults are code constants, so `apply/2` sets them when the player first spawns:

```elixir
def apply(%Player{} = s, %PlayerSpawned{player_id: pid, room_id: rid}) do
  %Player{s | id: pid, current_room_id: rid,
    str: 12, dex: 12, con: 12, int: 12, wis: 12, cha: 12,
    level: 1, xp: 0, hp: 10, max_hp: 10, mana: 10, max_mana: 10}
end
```

### 2.3 New command — `AwardXp` (`commands/award_xp.ex`)

```
%AwardXp{player_id, amount, award_id, source}
```
- `amount` — positive integer XP to add.
- `award_id` — deterministic idempotency key (e.g. `"quest:" <> quest_id`).
- `source` — provenance tag (e.g. `{:quest, quest_id}`) for logging/telemetry.

Routed to `Player` via `router.ex` (`dispatch([SpawnPlayer, MovePlayer, RecordRoomDiscovery, AwardXp], to: Player)`), dispatched with `consistency: :strong` from the facade.

### 2.4 `execute(%Player{}, %AwardXp{})`

```
if amount <= 0 or MapSet.member?(applied_award_ids, award_id) -> :ok   # no event (idempotent / zero-XP no-op)
else
  new_total = xp + amount
  new_level = LevelCurve.level_for_xp(new_total)
  base = %PlayerXpAwarded{player_id, amount, new_total, award_id}
  if new_level > level -> [base, %PlayerLeveledUp{player_id, from_level: level, to_level: new_level}]
  else [base]
```

Multi-level jumps are inherent: `new_level` is the curve's answer for `new_total`, which may be ≥ 2 above `level` (Edge case "Multi-level jump"). Only one `PlayerLeveledUp` is emitted, naming the final level.

### 2.5 New events

- `%PlayerXpAwarded{player_id, amount, new_total, award_id, version: 1}` — `apply/2` sets `xp: new_total` and `applied_award_ids: MapSet.put(ids, award_id)`.
- `%PlayerLeveledUp{player_id, from_level, to_level, version: 1}` — `apply/2` sets `level: to_level`.

Both `@derive Jason.Encoder`.

---

## 3. Write side — Quest XP threading

- **`FinalizeQuest` command** (`commands/finalize_quest.ex`): add `reward_xp` (integer, default 0).
- **`commands.ex` `finalize_quest/2`**: read `reward_xp = reward["xp"] || 0` next to the existing `reward["name"]/["description"]` reads (`commands.ex:747-749`); pass into `%FinalizeQuest{reward_xp: ...}`.
- **`Quest` aggregate** (`quest.ex:77-112`): thread `reward_xp` into the emitted `%QuestCompleted{}`.
- **`QuestCompleted` event** (`events/quest_completed.ex`): add `xp` (integer, default 0). `@enforce_keys` unchanged (xp defaults to 0 for old/authorless quests).

No change to `QuestRewardMinted` (item reward) or the item-minting projector path.

---

## 4. XP award handler — `World.Progression.XpAwarder`

A named `Commanded.Event.Handler` (`consistency: :eventual`), registered in `application.ex` alongside `NpcMinds.LifecycleManager`:

```elixir
def handle(%QuestCompleted{player_id: pid, quest_id: qid, xp: xp}, _meta) when is_integer(xp) and xp > 0 do
  Commands.award_xp(pid, xp, "quest:" <> qid)
  :ok
end
def handle(%QuestCompleted{}, _), do: :ok   # zero/absent XP → nothing
```

Exclusive single cluster-wide subscriber ⇒ exactly one node awards. Idempotency lives on the aggregate (`award_id`), so a redelivered `QuestCompleted` is a safe no-op.

---

## 5. Read side — schema + migration

### 5.1 Columns

| Table | Added columns |
|---|---|
| `player_state` | `str,dex,con,int,wis,cha` (int, default 12), `level` (int, default 1), `xp` (int, default 0), `hp,max_hp,mana,max_mana` (int, default 10) |
| `npc_clones` | `str,dex,con,int,wis,cha` (default 12), `level` (default 1), `hp,max_hp,mana,max_mana` (default 10) — **no `xp`** |
| `blueprints` | `str,dex,con,int,wis,cha` (default 12), `level` (default 1), `max_hp,max_mana` (default 10) — base authoring for NPC kind; ignored for object kind |

One migration `<ts>_add_stats_columns.exs` with `alter table` for each. SQL defaults ensure pre-existing rows are valid before reseed.

Schemas updated: `schemas/player_state.ex`, `schemas/npc_clone.ex`, `schemas/blueprint.ex` add matching `field` entries.

### 5.2 Projectors

- **`PlayerStateProjector`**:
  - `handle(%PlayerSpawned{})` — extend the existing `Repo.insert!`/`on_conflict` to seed the stat columns with defaults.
  - `handle(%PlayerXpAwarded{player_id, new_total})` — set `xp: new_total` (idempotent update by primary key).
  - `handle(%PlayerLeveledUp{player_id, to_level})` — set `level: to_level`.
- **`EntityProjector.insert_npc/2`** — write the frozen stat columns from the `fields` map (via the tolerant `fval/2`), e.g. `str: fval(fields, :str)`, …, `hp: fval(fields, :max_hp)` (current initialized to max), `mana: fval(fields, :max_mana)`. Stays `on_conflict: :nothing` (replay-safe).

### 5.3 NPC stat freeze at spawn

`commands.ex` `spawn_npc_clone_row/3` (`:378-399`) and `spawn_npc_freeform/3` (`:1013-1040`) add stat keys to the `fields` map:
- From blueprint: `str: bp.str, …, level: bp.level, max_hp: bp.max_hp, max_mana: bp.max_mana`.
- Freeform (no blueprint): defaults (12 / level 1 / max_hp 10 / max_mana 10).

`EntityCloned` event is **unchanged** (stats ride inside the generic `fields` map — no event-shape change).

---

## 6. Pure modules

### 6.1 `World.LevelCurve`

- `@a 50`, `@b -50`, `@c 0`.
- `threshold(level)` → `@a*level*level + @b*level + @c` (cumulative XP to *reach* `level`; `threshold(1) == 0`).
- `level_for_xp(xp)` → largest integer `L ≥ 1` with `threshold(L) ≤ xp` (closed-form inverse of the quadratic, floored; clamped to ≥ 1). Monotonic non-decreasing (FR-008).
- `progress(xp)` → `%{level: L, into_level: xp - threshold(L), to_next: threshold(L+1) - threshold(L), fraction: into_level / to_next}` for the XP bar and the "N xp to level L+1" caption. Always well-defined (unbounded curve).

### 6.2 `World.Stats` — banding (pure) + read

- `health_tier(cur, max)` → `{atom, sentence}` from `pct = cur/max*100`: `≥90 :very_healthy "Very healthy"`, `65–89 :healthy "Healthy"`, `35–64 :weakened "Weakened"`, `10–34 :very_weakened "Very Weakened"`, `<10 :deaths_door "At death's door"`. `max ≤ 0` guarded to `:deaths_door`.
- `relative_power(examiner_level, target_level)` → phrase from `d = target_level - examiner_level`: `≤ -4 "Much weaker"`, `-3..-2 "weaker"`, `-1..+1 "about as powerful"`, `+2..+3 "more powerful"`, `≥ +4 "too powerful to even compare"`.
- `for_player(player_id)` → the character-sheet map (§7).

---

## 7. Character-sheet read shape (`Stats.for_player/1`)

```elixir
%{
  name: username,
  level: level,
  xp: %{into_level: into, to_next: span, fraction: frac},   # from LevelCurve.progress/1
  hp: %{cur: hp, max: max_hp},
  mana: %{cur: mana, max: max_mana},
  abilities: [
    %{name: "STR", value: str, modifier: mod(str)}, %{name: "DEX", ...}, %{name: "CON", ...},
    %{name: "INT", ...}, %{name: "WIS", ...}, %{name: "CHA", ...}
  ]
}
```

Consumed by `primitives.ex` `stats_panel/1` (sidebar) and `player_modals.ex` `stats_modal/1` (modal). Replaces the mock `%{name, class, hp, mp, xp}` shape and `GameData.ability_scores/0`.

---

## 8. Examine — `Examine.Match` additions

`examine/match.ex` defstruct adds `:health_tier` (sentence string) and `:power_phrase` (string or nil).

- `npc_match/1` and `player_match/1` populate both from the target row's `hp/max_hp/level` and the examiner's `level`.
- Self-examination (`~w(__self__ me self)`): `:power_phrase = nil` (FR-021); health tier optional/omitted for self.
- Render: `player_commands.ex look_target/4` carries the fields into the `:detail` entry; `log_entry.ex` object/npc/player branches render the health line and (when present) the power line.
- **Never** renders raw ability/level/xp/mana numbers (FR-020).

---

## 9. Broadcast / LiveView

- `UIEvents.PlayerStatsChanged{player_id, stats, xp_gained, leveled_to}` (new struct in `ui_events.ex`).
- `UIEventBroadcaster` witnesses `PlayerXpAwarded` (→ `xp_gained`) and `PlayerLeveledUp` (→ `leveled_to`) and broadcasts `PlayerStatsChanged` with the refreshed `Stats.for_player/1` on `Topics.player_topic(player_id)`.
- `game_live.ex` `handle_info(%PlayerStatsChanged{})` → `GameLive.UIEvents.stats_changed/2`: `assign(:stats, msg.stats)`, then `append_log(%{kind: :system, text: "You gain #{xp_gained} experience."})` and, if `leveled_to`, `append_log(%{kind: :system, text: "You are now level #{leveled_to}!"})`.

---

## 10. Validation rules (from requirements)

- Player defaults exactly: abilities 12, level 1, xp 0, hp 10/10, mana 10/10 (FR-005) — asserted at spawn.
- NPC stats frozen per instance; two clones of one blueprint have independent `hp`/`mana` (FR-007) — independent rows.
- XP award: players only; no NPC path exists (FR-012) — there is no NPC `AwardXp` route.
- Level recomputed only on award; stable between awards (FR-009); NPC level never derived (FR-010).
- Level-up changes only `level` (FR-011a) — `apply(PlayerLeveledUp)` touches no other field.
- Examine leaks no exact numbers (FR-020); self omits power phrase (FR-021).
- Stats persist across sessions (FR-024) — they are in the durable event store (players) / read model, rebuilt on projection.
