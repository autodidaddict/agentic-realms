defmodule AgenticRealms.World.LevelCurve do
  @moduledoc """
  Feature 019 — the player level curve.

  A D&D-style compounding quadratic mapping cumulative experience to level:
  `threshold(L) = a·L² + b·L + c` with `threshold(1) == 0`. Unbounded (no
  level cap), monotonic non-decreasing. Pure and DB-free (unit-tested without
  the database). Coefficients are module constants so the curve is tunable
  without touching call sites.

  Concrete thresholds: 0, 100, 300, 600, 1000, 1500, 2100, …
  """

  @a 50
  @b -50
  @c 0

  @doc "Cumulative experience required to *reach* `level` (>= 1)."
  @spec threshold(pos_integer()) :: non_neg_integer()
  def threshold(level) when is_integer(level) and level >= 1 do
    @a * level * level + @b * level + @c
  end

  @doc """
  The level for a cumulative experience total: the largest `L >= 1` with
  `threshold(L) <= xp`. Monotonic non-decreasing; clamps to 1 for xp <= 0.
  """
  @spec level_for_xp(integer()) :: pos_integer()
  def level_for_xp(xp) when is_integer(xp) and xp <= 0, do: 1

  def level_for_xp(xp) when is_integer(xp) do
    # Closed-form inverse of the quadratic, corrected for floating-point error
    # at exact thresholds by nudging to the true integer boundary.
    approx = trunc((50 + :math.sqrt(2500 + 200 * xp)) / 100)
    approx |> max(1) |> correct(xp)
  end

  defp correct(level, xp) do
    cond do
      threshold(level + 1) <= xp -> correct(level + 1, xp)
      level > 1 and threshold(level) > xp -> correct(level - 1, xp)
      true -> level
    end
  end

  @doc """
  Progress toward the next level for a cumulative experience total.

  Returns `%{level, into_level, to_next, fraction}` where `fraction` is in
  `[0, 1)`. Always defined — the curve is unbounded, so there is always a next
  level threshold.
  """
  @spec progress(integer()) :: %{
          level: pos_integer(),
          into_level: non_neg_integer(),
          to_next: pos_integer(),
          fraction: float()
        }
  def progress(xp) when is_integer(xp) do
    xp = max(xp, 0)
    level = level_for_xp(xp)
    base = threshold(level)
    span = threshold(level + 1) - base
    into = xp - base
    %{level: level, into_level: into, to_next: span, fraction: into / span}
  end
end
