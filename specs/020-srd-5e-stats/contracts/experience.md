# Contract: `Srd.Rules.Experience`

**Package**: `packages/srd_5e` | **Feature**: 020-srd-5e-stats (FR-028, FR-029, FR-030)

The SRD 5.2 experience table and the calculations over it. Pure, no state, no options. SRD 5.1 and 5.2 carry the same table, so unlike the rules ADR-0003 lists as divergent, nothing here takes an `edition:`.

Placed under `Srd.Rules` next to `Proficiency`, whose level schedule this table is the counterpart to.

## Functions

### `max_level() :: pos_integer()`

Returns `20`. The table's last entry, and the cap every other function respects.

### `table() :: [{pos_integer(), non_neg_integer()}]`

The twenty `{level, threshold}` pairs in ascending level order. Exposed so a consumer can render the whole progression without twenty calls.

### `threshold(level) :: non_neg_integer()`

Cumulative experience required to reach `level`. Raises `FunctionClauseError` outside `1..20` — a level off the table is a caller bug, not a value to clamp.

```elixir
Experience.threshold(1)   #=> 0
Experience.threshold(2)   #=> 300
Experience.threshold(5)   #=> 6_500
Experience.threshold(20)  #=> 355_000
```

### `level_for_xp(xp) :: pos_integer()`

The highest level whose threshold is at or below `xp`. Monotonic non-decreasing. Clamps to `1` at or below 0 XP and to `20` above the level 20 threshold — a total function, because it is called with whatever total a player has accumulated.

```elixir
Experience.level_for_xp(0)         #=> 1
Experience.level_for_xp(299)       #=> 1
Experience.level_for_xp(300)       #=> 2      # exact threshold
Experience.level_for_xp(-50)       #=> 1
Experience.level_for_xp(9_999_999) #=> 20     # capped
```

### `progress(xp) :: map()`

Progress toward the next level.

```elixir
%{
  level:      pos_integer(),      # level_for_xp(xp)
  into_level: non_neg_integer(),  # xp - threshold(level)
  to_next:    pos_integer() | nil,# threshold(level + 1) - threshold(level); nil at 20
  fraction:   float(),            # into_level / to_next, in [0.0, 1.0); 1.0 at 20
  maxed?:     boolean()           # level == max_level()
}
```

`to_next: nil` with `fraction: 1.0` at level 20 is the one place this module's shape differs from the unbounded `World.LevelCurve` it replaces. Callers rendering a bar treat `maxed?` as full.

```elixir
Experience.progress(0)
#=> %{level: 1, into_level: 0, to_next: 300, fraction: 0.0, maxed?: false}

Experience.progress(450)
#=> %{level: 2, into_level: 150, to_next: 600, fraction: 0.25, maxed?: false}

Experience.progress(400_000)
#=> %{level: 20, into_level: 45_000, to_next: nil, fraction: 1.0, maxed?: true}
```

Negative input is treated as 0.

## Tests

`test/srd/rules/experience_test.exs`, `async: true`, following the package's `describe`-per-function convention.

Required coverage (SC-009):

- every one of the twenty thresholds maps to its own level;
- every threshold minus one maps to the level below;
- `level_for_xp/1` at 0, below 0, and far above the level 20 threshold;
- `progress/1` at the bottom of a band, mid-band, and at level 20;
- `threshold/1` raises outside `1..20`;
- `table/1` has twenty ascending, strictly increasing entries.

## Package housekeeping

- `CHANGELOG.md` gains an `[Unreleased]` entry.
- The `Srd` moduledoc's character-building example is a reasonable place to mention progression, but is not required.
