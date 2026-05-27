# Contract: Direction module expansion + Direction.Geometry

## `AgenticRealms.World.Direction` (extended)

### Canonical set (changed)

```elixir
@canonical [
  :north, :south, :east, :west,
  :northeast, :northwest, :southeast, :southwest,
  :up, :down
]
```

### `parse/1` (extended)

Accept the new aliases. Whitespace, case, and the optional `"go "` prefix are stripped first (existing behavior).

| Input alias                                | Resolves to     |
|--------------------------------------------|-----------------|
| `"northeast"`, `"ne"`                      | `:northeast`    |
| `"northwest"`, `"nw"`                      | `:northwest`    |
| `"southeast"`, `"se"`                      | `:southeast`    |
| `"southwest"`, `"sw"`                      | `:southwest`    |
| (existing) `"north"`, `"n"`, etc.          | unchanged       |

Other strings → `:error` (unchanged).

### `opposite/1` (extended)

```elixir
def opposite(:northeast), do: :southwest
def opposite(:southwest), do: :northeast
def opposite(:northwest), do: :southeast
def opposite(:southeast), do: :northwest
# (existing clauses unchanged)
```

### `to_string/1` (extended)

```elixir
def to_string(:northeast), do: "northeast"
def to_string(:northwest), do: "northwest"
def to_string(:southeast), do: "southeast"
def to_string(:southwest), do: "southwest"
def to_string(s) when s in ["northeast","northwest","southeast","southwest"], do: s
# (existing clauses unchanged)
```

### Behaviors NOT changed

- The existing parse for `"n"`, `"s"`, etc. is preserved.
- The existing default behavior for invalid input is preserved (`:error`).
- Existing tests pass without modification; new tests cover the four new directions.

---

## `AgenticRealms.World.Direction.Geometry` (NEW)

A pure module. No I/O, no Repo, no aggregate references. Operates on direction atoms and Room structs (or any map with `:elevation`, `:map_x`, `:map_y` keys).

### `delta/1`

```elixir
@type planar_delta :: {dx_sign :: -1 | 0 | 1, dy_sign :: -1 | 0 | 1}

@spec delta(atom()) ::
        {:planar, planar_delta()} |
        {:vertical, dz_sign :: -1 | 1}

def delta(:north),     do: {:planar, {0, -1}}
def delta(:south),     do: {:planar, {0, 1}}
def delta(:east),      do: {:planar, {1, 0}}
def delta(:west),      do: {:planar, {-1, 0}}
def delta(:northeast), do: {:planar, {1, -1}}
def delta(:northwest), do: {:planar, {-1, -1}}
def delta(:southeast), do: {:planar, {1, 1}}
def delta(:southwest), do: {:planar, {-1, 1}}
def delta(:up),        do: {:vertical, 1}
def delta(:down),      do: {:vertical, -1}
```

Note the screen-coordinate convention (y increases downward) per the spec's assumption section.

### `consistent?/3`

```elixir
@spec consistent?(direction :: atom(), source :: %{...}, target :: %{...}) ::
        :ok | {:error, atom()}

# Off-map skip: if either room is missing coordinates, return :ok (FR-024)
def consistent?(_direction, %{map_x: nil}, _target), do: :ok
def consistent?(_direction, %{map_y: nil}, _target), do: :ok
def consistent?(_direction, _source, %{map_x: nil}), do: :ok
def consistent?(_direction, _source, %{map_y: nil}), do: :ok

# Planar directions: same elevation, target along the direction's ray, distance >= 1
def consistent?(direction, source, target) do
  case delta(direction) do
    {:planar, {dx_sign, dy_sign}} ->
      cond do
        source.elevation != target.elevation ->
          {:error, :elevation_mismatch_for_planar_exit}

        not on_ray?(source, target, dx_sign, dy_sign) ->
          {:error, :off_axis_for_direction}

        true ->
          :ok
      end

    {:vertical, dz_sign} ->
      cond do
        source.map_x != target.map_x or source.map_y != target.map_y ->
          {:error, :horizontal_offset_for_vertical_exit}

        sign(target.elevation - source.elevation) != dz_sign ->
          {:error, :wrong_vertical_direction}

        target.elevation == source.elevation ->
          {:error, :no_elevation_change_for_vertical_exit}

        true ->
          :ok
      end
  end
end

defp on_ray?(s, t, dx_sign, dy_sign) do
  dx = t.map_x - s.map_x
  dy = t.map_y - s.map_y
  cond do
    # Pure cardinal: one delta must be zero, the other non-zero with the correct sign
    dx_sign == 0 -> dx == 0 and sign(dy) == dy_sign and dy != 0
    dy_sign == 0 -> dy == 0 and sign(dx) == dx_sign and dx != 0
    # Diagonal: |dx| == |dy|, with both signs matching
    true -> abs(dx) == abs(dy) and sign(dx) == dx_sign and sign(dy) == dy_sign and dx != 0
  end
end

defp sign(0), do: 0
defp sign(n) when n > 0, do: 1
defp sign(n) when n < 0, do: -1
```

### `unit_vector/1`

Returns the unit-length direction vector in screen coordinates, used by the renderer to angle fog stubs and to compute line endpoints:

```elixir
@spec unit_vector(atom()) :: {dx :: float(), dy :: float()}

def unit_vector(:north),     do: {0.0, -1.0}
def unit_vector(:south),     do: {0.0, 1.0}
def unit_vector(:east),      do: {1.0, 0.0}
def unit_vector(:west),      do: {-1.0, 0.0}
def unit_vector(:northeast), do: {0.7071067811865475, -0.7071067811865475}
def unit_vector(:northwest), do: {-0.7071067811865475, -0.7071067811865475}
def unit_vector(:southeast), do: {0.7071067811865475, 0.7071067811865475}
def unit_vector(:southwest), do: {-0.7071067811865475, 0.7071067811865475}
# :up and :down have no planar projection — calling unit_vector on them is a renderer bug
def unit_vector(:up),   do: raise(ArgumentError, "vertical direction has no planar unit vector")
def unit_vector(:down), do: raise(ArgumentError, "vertical direction has no planar unit vector")
```

The renderer ONLY calls `unit_vector/1` for planar directions (when computing fog-stub endpoints). Vertical exits do not produce lines — they produce icons on the source room (FR-009).
