# Contract: Read & Display (Real Stats)

Read-side contracts consumed by the LiveView. All numbers shown on a player's **own** sheet; examine shows only qualitative bands.

## `World.LevelCurve` (pure)

Compounding quadratic, unbounded. `@a 50`, `@b -50`, `@c 0`.

| Function | Returns | Contract |
|---|---|---|
| `threshold(level)` | integer | Cumulative XP to reach `level`. `threshold(1) == 0`, `threshold(2)==100`, `threshold(3)==300`, `threshold(4)==600`, `threshold(5)==1000`. |
| `level_for_xp(xp)` | integer ≥ 1 | Largest `L` with `threshold(L) ≤ xp`. Monotonic non-decreasing. `level_for_xp(0)==1`, `level_for_xp(99)==1`, `level_for_xp(100)==2`, `level_for_xp(1000)==5`. |
| `progress(xp)` | `%{level, into_level, to_next, fraction}` | `into_level = xp - threshold(level)`; `to_next = threshold(level+1) - threshold(level)`; `fraction = into_level/to_next ∈ [0,1)`. Always defined (no cap). |

## `World.Stats.for_player/1` — character-sheet shape

```elixir
%{
  name:  String.t(),
  level: pos_integer(),
  xp:    %{into_level: non_neg_integer(), to_next: pos_integer(), fraction: float()},
  hp:    %{cur: non_neg_integer(), max: pos_integer()},
  mana:  %{cur: non_neg_integer(), max: pos_integer()},
  abilities: [%{name: "Strength"|"Dexterity"|"Constitution"|"Intelligence"|"Wisdom"|"Charisma", value: integer()}]  # length 6, STR..CHA order
}
```

- Abilities are shown by full name (not the 3-letter abbreviation). No D&D "modifier" is shown — it was mockup carryover, not a spec stat.
- New player → `%{name: username, level: 1, xp: %{into_level: 0, to_next: 100, fraction: 0.0}, hp: %{cur: 10, max: 10}, mana: %{cur: 10, max: 10}, abilities: [12×6 …]}` (SC-001).

### UI mapping

- **Sidebar** `primitives.ex stats_panel/1`: name + sigil (first letter of name); `hp_bar` Health (`hp`), Mana (`mana`), Experience (`kind="xp"`, `cur: into_level, max: to_next`). **No class pill.**
- **Modal** `player_modals.ex stats_modal/1`: same bars; the "N xp to level L+1" caption = `to_next - into_level` and `level + 1`; ability rows from `abilities`. **No class, no deity lore, no mana flavor captions.**
- The sheet MUST show **only** name, level, XP/progress, HP, mana, and the six abilities (SC-002).

## Examine output (`Examine.Match` + render)

Extends today's examine of a player/NPC with two appended lines:

1. **Health line** — `Stats.health_tier(cur, max)` sentence: `Very healthy` (≥90% max HP) · `Healthy` (65–89) · `Weakened` (35–64) · `Very Weakened` (10–34) · `At death's door` (<10, incl. 0).
2. **Power line** — `Stats.relative_power(examiner_level, target_level)` phrase: `Much weaker` (Δ≤−4) · `weaker` (−3..−2) · `about as powerful` (−1..+1) · `more powerful` (+2..+3) · `too powerful to even compare` (Δ≥+4). Δ = target − examiner. **Omitted when examining self** (FR-021).

**Contract**: examine output contains **no** exact number for any ability score, level, XP, or mana of the target (FR-020); HP appears only as tier 1, mana not at all.

## Notices (log window)

Emitted by `GameLive.UIEvents.stats_changed/2` via `append_log` with the existing `:system` kind:

- On XP gain: `"You gain <amount> experience."` (FR-022).
- On level-up (additionally): `"You are now level <to_level>!"` (FR-023).

Delivered by `UIEvents.PlayerStatsChanged{player_id, stats, xp_gained, leveled_to}` broadcast on `Topics.player_topic(player_id)` (private to the earning player).
