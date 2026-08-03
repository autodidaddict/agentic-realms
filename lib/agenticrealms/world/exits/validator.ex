defmodule AgenticRealms.World.Exits.Validator do
  @moduledoc """
  Pre-dispatch validator for `AddExit`: a strict direction axis and a
  flexible distance, for exits between two rooms with coordinates.

  Delegates the geometric check to `Direction.Geometry.consistent?/3` and
  wraps any error into `{:error, {:exit_geometry_violation, reason}}` so
  callers can pattern-match on the violation shape.

  Off-map exits (either room missing coords) are accepted unconditionally,
  which is the supported pattern for wormhole-like exits.

  This module does NOT verify room existence, direction-uniqueness on the
  source room, or any aggregate-level invariants. Those are the caller's
  responsibility. The validator only answers one question: do the source's
  coordinates, the target's coordinates, and the exit direction agree
  geometrically?
  """

  alias AgenticRealms.World.Direction.Geometry

  @doc """
  Check geometric consistency of an exit direction against the source and
  target rooms' positions. Returns `:ok` or
  `{:error, {:exit_geometry_violation, reason_atom}}`.

  Geometric consistency is checked ONLY between rooms in the same region.
  Cross-region exits (where `source.region_id != target.region_id`) skip
  the check unconditionally — each region defines its own coordinate plane,
  so cross-region coordinate deltas have no meaning. The cross-region
  visual treatment in the renderer (dashed line + portal glyph) makes the
  semantics of these exits clear to the player.

  Off-map rooms (either side with unset coords) also skip the check, per
  FR-024's wormhole-pattern clause.
  """
  @spec consistent?(atom(), map(), map()) ::
          :ok | {:error, {:exit_geometry_violation, atom()}}
  def consistent?(:rift, _source, _target), do: :ok

  def consistent?(direction, source, target) do
    if cross_region?(source, target) do
      :ok
    else
      case Geometry.consistent?(direction, source, target) do
        :ok -> :ok
        {:error, reason} -> {:error, {:exit_geometry_violation, reason}}
      end
    end
  end

  defp cross_region?(%{region_id: a}, %{region_id: b})
       when not is_nil(a) and not is_nil(b),
       do: a != b

  defp cross_region?(_, _), do: false
end
