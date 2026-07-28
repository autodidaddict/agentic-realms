defmodule Srd.Rules.Experience do
  @moduledoc """
  The experience table and character advancement.

  SRD 5.2 advances a character on a fixed table of twenty thresholds rather than
  a formula, and stops at level 20. This is the counterpart to
  `Srd.Rules.Proficiency`, whose bonus is keyed to the level this module hands
  back.

  SRD 5.1 and 5.2 carry the same table, so nothing here takes an `edition:`
  option.
  """

  @table [
    {1, 0},
    {2, 300},
    {3, 900},
    {4, 2_700},
    {5, 6_500},
    {6, 14_000},
    {7, 23_000},
    {8, 34_000},
    {9, 48_000},
    {10, 64_000},
    {11, 85_000},
    {12, 100_000},
    {13, 120_000},
    {14, 140_000},
    {15, 165_000},
    {16, 195_000},
    {17, 225_000},
    {18, 265_000},
    {19, 305_000},
    {20, 355_000}
  ]

  @thresholds Map.new(@table)
  @max_level @table |> List.last() |> elem(0)

  @typedoc "Progress toward the next level, or the absence of one at the cap."
  @type progress :: %{
          level: pos_integer(),
          into_level: non_neg_integer(),
          to_next: pos_integer() | nil,
          fraction: float(),
          maxed?: boolean()
        }

  @doc """
  The highest level the table defines.

      iex> Srd.Rules.Experience.max_level()
      20
  """
  @spec max_level() :: pos_integer()
  def max_level, do: @max_level

  @doc """
  Every `{level, threshold}` pair, in ascending level order.
  """
  @spec table() :: [{pos_integer(), non_neg_integer()}]
  def table, do: @table

  @doc """
  Cumulative experience required to reach `level`.

  Raises outside `1..#{@max_level}` — a level off the table is a caller bug, not
  a value to clamp.

      iex> Srd.Rules.Experience.threshold(5)
      6500
  """
  @spec threshold(pos_integer()) :: non_neg_integer()
  def threshold(level) when is_integer(level) and level >= 1 and level <= @max_level do
    Map.fetch!(@thresholds, level)
  end

  @doc """
  The level for a cumulative experience total: the highest level whose threshold
  is at or below `xp`.

  Total, unlike `threshold/1`, because it is called with whatever total a
  character has accumulated. Clamps to 1 at or below zero and to
  #{@max_level} above the last threshold.

      iex> Srd.Rules.Experience.level_for_xp(299)
      1
      iex> Srd.Rules.Experience.level_for_xp(300)
      2
  """
  @spec level_for_xp(integer()) :: pos_integer()
  def level_for_xp(xp) when is_integer(xp) do
    @table
    |> Enum.reduce(1, fn {level, at}, acc -> if xp >= at, do: level, else: acc end)
  end

  @doc """
  Progress toward the next level.

  At the cap there is no next threshold, so `:to_next` is `nil` and `:fraction`
  is `1.0`. Callers rendering a bar treat `:maxed?` as full. Experience past the
  cap still accumulates in `:into_level`.

      iex> Srd.Rules.Experience.progress(450)
      %{level: 2, into_level: 150, to_next: 600, fraction: 0.25, maxed?: false}
  """
  @spec progress(integer()) :: progress()
  def progress(xp) when is_integer(xp) do
    xp = max(xp, 0)
    level = level_for_xp(xp)
    into = xp - threshold(level)

    if level == @max_level do
      %{level: level, into_level: into, to_next: nil, fraction: 1.0, maxed?: true}
    else
      span = threshold(level + 1) - threshold(level)
      %{level: level, into_level: into, to_next: span, fraction: into / span, maxed?: false}
    end
  end
end
