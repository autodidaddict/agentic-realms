# Contract: `Srd.Rules.Hitpoints` additions

**Package**: `packages/srd_5e` | **Feature**: 020-srd-5e-stats (FR-006, FR-013)

`Srd.Rules.Hitpoints` currently models a hit point *pool* and what damage and healing do to it. It says nothing about how large that pool should be, so the game would have to compute maximum hitpoints itself, which FR-006 forbids. Two functions close the gap.

Both take a hit die as a `Srd.Dice.Expr` or dice notation, matching how `Srd.Content.Class` carries `:hit_die`.

## `starting(hit_die, con_modifier) :: pos_integer()`

Maximum hitpoints at level 1: the hit die's maximum plus the Constitution modifier, floored at 1.

```elixir
Hitpoints.starting("1d10", 2)   #=> 12
Hitpoints.starting("1d6", -3)   #=> 3
Hitpoints.starting("1d6", -9)   #=> 1     # floored
```

The floor matters: the SRD has no notion of a character created at 0 hitpoints, and a low-Constitution wizard would otherwise start dead.

## `per_level(hit_die, con_modifier) :: integer()`

Hitpoints gained per level after the first, using the SRD's fixed-value option: half the die rounded up, plus one, plus the Constitution modifier.

```elixir
Hitpoints.per_level("1d10", 2)  #=> 8     # (10/2 + 1) + 2
Hitpoints.per_level("1d8", 0)   #=> 5
Hitpoints.per_level("1d6", -1)  #=> 3
```

Not floored. A character whose per-level gain is zero or negative is a legal, if unfortunate, SRD character; the floor belongs on the total, which is the caller's business.

The rolled alternative (actually rolling the hit die on level-up) is deliberately absent. Nothing in the game rolls for hitpoints, and adding a rolled variant now would be a function with no caller.

## `maximum(hit_die, level, con_modifier) :: pos_integer()`

The total for a character of `level` levels in one class, composed from the two above and floored at 1.

```elixir
Hitpoints.maximum("1d10", 1, 2)   #=> 12     # starting only
Hitpoints.maximum("1d10", 3, 2)   #=> 28     # 12 + 8 + 8
Hitpoints.maximum("1d6", 5, -3)   #=> 3      # floored
```

Multiclassing is out of scope for this feature and for this function. It takes one die and one level.

## `hit_dice(hit_die, level) :: Srd.Dice.Expr.t()`

The character's hit dice pool: the class die with its count set to the level.

```elixir
Hitpoints.hit_dice("1d10", 3)   #=> %Srd.Dice.Expr{count: 3, sides: 10, modifier: 0}
```

Returned as an `Expr` rather than a string so a caller can roll it directly on a short rest, and so rendering stays the caller's choice.

## Tests

Added to `test/srd/rules/hitpoints_test.exs` as two new `describe` blocks:

- `starting/2` for every SRD hit die (d6, d8, d10, d12) at positive, zero, and negative Constitution;
- the floor at 1 for a Constitution modifier below the die's maximum;
- `per_level/2` for every hit die, verifying half-rounded-up plus one;
- `maximum/3` at level 1 (equal to `starting/2`), at several levels, and floored at 1;
- `hit_dice/2` returning an `Expr` whose count is the level and whose sides match the class die;
- notation and `Expr` accepted interchangeably by all four.
