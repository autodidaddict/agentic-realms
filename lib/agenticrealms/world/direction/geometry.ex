defmodule AgenticRealms.World.Direction.Geometry do
  @moduledoc """
  Pure geometric semantics for the 10 canonical directions. No I/O, no Repo,
  no aggregate references. Operates on direction atoms and Room-shaped maps
  (anything with `:map_x`, `:map_y`, `:elevation` keys).

  Feature 012 — Maps. See `specs/012-maps/contracts/direction.md`.

  ## Coordinate convention

  Screen coordinates: `y` increases DOWNWARD, so a "north" exit has
  `target.y < source.y`. The convention is internal to the renderer; it is
  documented here only because the `consistent?/3` rule encodes it.
  """

  @type planar_delta :: {dx_sign :: -1 | 0 | 1, dy_sign :: -1 | 0 | 1}
  @type direction :: atom()

  @doc """
  The unit-step delta for a direction.

  Planar directions return `{:planar, {dx_sign, dy_sign}}` — the signs of
  the coordinate deltas (NOT the magnitudes, since FR-024 allows variable
  distance along the direction axis).

  Vertical directions return `{:vertical, dz_sign}` — `+1` for `:up`,
  `-1` for `:down`.
  """
  @spec delta(direction()) ::
          {:planar, planar_delta()}
          | {:vertical, -1 | 1}
  def delta(:north), do: {:planar, {0, -1}}
  def delta(:south), do: {:planar, {0, 1}}
  def delta(:east), do: {:planar, {1, 0}}
  def delta(:west), do: {:planar, {-1, 0}}
  def delta(:northeast), do: {:planar, {1, -1}}
  def delta(:northwest), do: {:planar, {-1, -1}}
  def delta(:southeast), do: {:planar, {1, 1}}
  def delta(:southwest), do: {:planar, {-1, 1}}
  def delta(:up), do: {:vertical, 1}
  def delta(:down), do: {:vertical, -1}

  @doc """
  Check whether an exit's direction is geometrically consistent with the
  source and target rooms' coordinates and elevation, per FR-024.

  Returns `:ok` on consistency, `{:error, reason}` on violation. If EITHER
  room has unset coordinates (`map_x: nil` or `map_y: nil`), the check is
  skipped and `:ok` is returned — this is the supported pattern for
  wormhole-like exits (typically from an off-map hub room).

  ## Rules

    * Planar directions require `source.elevation == target.elevation` AND
      the target sits along the direction's axis ray from the source with
      a positive distance ≥ 1.
    * Diagonal directions require equal-magnitude `|Δx|` and `|Δy|` with
      both signs matching the diagonal's quadrant.
    * Vertical directions require `source.map_x == target.map_x` AND
      `source.map_y == target.map_y` AND the elevation delta's sign matches
      the direction.
  """
  @spec consistent?(direction(), map(), map()) :: :ok | {:error, atom()}
  def consistent?(_direction, %{map_x: nil}, _target), do: :ok
  def consistent?(_direction, %{map_y: nil}, _target), do: :ok
  def consistent?(_direction, _source, %{map_x: nil}), do: :ok
  def consistent?(_direction, _source, %{map_y: nil}), do: :ok

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

          target.elevation == source.elevation ->
            {:error, :no_elevation_change_for_vertical_exit}

          sign(target.elevation - source.elevation) != dz_sign ->
            {:error, :wrong_vertical_direction}

          true ->
            :ok
        end
    end
  end

  @doc """
  Unit-length direction vector in screen coordinates. Used by the SVG
  renderer to compute fog-stub line endpoints (the stub extends one cell
  into the direction from the source room's center).

  Raises for vertical directions — they have no planar projection and the
  renderer must not call this on `:up` or `:down`.
  """
  @spec unit_vector(direction()) :: {float(), float()}
  def unit_vector(:north), do: {0.0, -1.0}
  def unit_vector(:south), do: {0.0, 1.0}
  def unit_vector(:east), do: {1.0, 0.0}
  def unit_vector(:west), do: {-1.0, 0.0}
  def unit_vector(:northeast), do: {0.7071067811865475, -0.7071067811865475}
  def unit_vector(:northwest), do: {-0.7071067811865475, -0.7071067811865475}
  def unit_vector(:southeast), do: {0.7071067811865475, 0.7071067811865475}
  def unit_vector(:southwest), do: {-0.7071067811865475, 0.7071067811865475}

  def unit_vector(d) when d in [:up, :down] do
    raise ArgumentError,
          "vertical direction #{inspect(d)} has no planar unit vector; " <>
            "vertical exits render as icons on the source room, not lines"
  end

  @planar_directions [
    :north,
    :south,
    :east,
    :west,
    :northeast,
    :northwest,
    :southeast,
    :southwest
  ]

  @doc """
  Whether a direction is a planar (compass) direction. Convenience for
  callers that need to branch between planar and vertical rendering paths.
  """
  @spec planar?(direction()) :: boolean()
  def planar?(d) when d in @planar_directions, do: true
  def planar?(_), do: false

  defp on_ray?(s, t, dx_sign, dy_sign) do
    dx = t.map_x - s.map_x
    dy = t.map_y - s.map_y

    cond do
      dx_sign == 0 ->
        dx == 0 and dy != 0 and sign(dy) == dy_sign

      dy_sign == 0 ->
        dy == 0 and dx != 0 and sign(dx) == dx_sign

      true ->
        dx != 0 and abs(dx) == abs(dy) and sign(dx) == dx_sign and sign(dy) == dy_sign
    end
  end

  defp sign(0), do: 0
  defp sign(n) when n > 0, do: 1
  defp sign(n) when n < 0, do: -1
end
