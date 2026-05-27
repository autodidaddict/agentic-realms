# Contract: Exits.Validator

## Module: `AgenticRealms.World.Exits.Validator`

Single-function pre-dispatch validator wired into `Commands.add_exit/3`. Delegates the geometric check to `Direction.Geometry.consistent?/3` and produces a wizard-readable error tuple on rejection.

### Function

```elixir
@spec consistent?(
        direction :: atom(),
        source :: %Room{} | %{map_x: integer | nil, map_y: integer | nil, elevation: integer},
        target :: %Room{} | %{map_x: integer | nil, map_y: integer | nil, elevation: integer}
      ) :: :ok | {:error, {:exit_geometry_violation, atom()}}

def consistent?(direction, source, target) do
  case AgenticRealms.World.Direction.Geometry.consistent?(direction, source, target) do
    :ok -> :ok
    {:error, reason} -> {:error, {:exit_geometry_violation, reason}}
  end
end
```

### Accept matrix (returns `:ok`)

| Scenario                                                                                   | Reason                                              |
|--------------------------------------------------------------------------------------------|-----------------------------------------------------|
| Source has no coords                                                                       | FR-024 off-map skip                                 |
| Target has no coords                                                                       | FR-024 off-map skip                                 |
| `source.region_id != target.region_id` (cross-region exit)                                 | Independent coord planes — geometry is meaningless across regions; the cross-region renderer affordance carries the semantics. |
| Planar direction; same region; same elevation; target on the correct axis ray, any distance ≥ 1 | FR-024 strict-direction / flexible-distance         |
| Vertical direction; same region; same `(map_x, map_y)`; elevation delta has the correct sign, any magnitude ≥ 1 | FR-024 vertical direction rule              |

### Reject matrix (returns `{:error, {:exit_geometry_violation, reason}}`)

| Scenario                                                                                    | Reason atom                                  |
|---------------------------------------------------------------------------------------------|----------------------------------------------|
| Planar direction; source.elevation ≠ target.elevation                                       | `:elevation_mismatch_for_planar_exit`        |
| Planar direction; target is not on the direction's axis ray                                 | `:off_axis_for_direction`                    |
| Planar direction; target is on the axis ray but in the wrong sign (e.g., "north" with target.y > source.y) | `:off_axis_for_direction`            |
| Vertical direction; source.x ≠ target.x or source.y ≠ target.y                              | `:horizontal_offset_for_vertical_exit`       |
| Vertical direction; elevation delta has the wrong sign                                      | `:wrong_vertical_direction`                  |
| Vertical direction; elevation delta is zero                                                 | `:no_elevation_change_for_vertical_exit`     |

### Call sites

- `AgenticRealms.World.Commands.add_exit/3` — direct usage. Failure short-circuits before aggregate dispatch.
- (Future) Wizard authoring UI — same validator, surfaced as a real-time form-level error.

### Test plan

A single accept/reject matrix test in `test/agenticrealms/world/exits/validator_test.exs`:

- 10 directions × 4 source/target shapes (both on-map / source off-map / target off-map / both off-map) × representative distances (adjacent, distance=5, opposite-axis-mismatch, wrong-sign).
- ~40 generated test cases via ExUnit's `for` comprehension.

### What the validator does NOT do

- Does NOT check for room existence (caller's responsibility — `Commands.add_exit/3` fetches both rooms first).
- Does NOT check for direction-already-occupied on the source room (existing aggregate-level invariant in `Room.execute/2`).
- Does NOT block exits between rooms in different regions (cross-region exits are explicitly supported per FR-008 / Spec Assumptions). The validator detects the cross-region case via `source.region_id != target.region_id` and SKIPS the geometric check entirely — the two regions have independent coordinate planes, so comparing their (x, y) values is meaningless. The cross-region renderer affordance (dashed line + portal glyph) handles the semantics on the UI side.
- Does NOT verify map-visibility or discovery — those are render-layer concerns.
