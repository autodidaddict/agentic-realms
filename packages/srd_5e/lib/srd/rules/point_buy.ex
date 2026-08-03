defmodule Srd.Rules.PointBuy do
  @moduledoc """
  The SRD's "Customizing Ability Scores" variant: a budget of points spent on
  the six abilities, rather than a fixed array assigned to them.

  Every score starts at 8 and costs nothing. Raising it costs from the table
  below, and the last two steps cost double, which is what stops every
  character buying a 15 in everything that matters.

      8  → 0      12 → 4
      9  → 1      13 → 5
      10 → 2      14 → 7
      11 → 3      15 → 9

  Scores here are what the player bought. Species and background increases are
  applied *after* this and are not subject to the budget or the ceiling, so a
  final score above `max_score/0` is normal and not this module's business.

  Like the rest of this library, it answers what may be spent, never what was.
  Choosing a spread for a particular character is the caller's problem.
  """

  @budget 27
  @min 8
  @max 15

  @costs %{8 => 0, 9 => 1, 10 => 2, 11 => 3, 12 => 4, 13 => 5, 14 => 7, 15 => 9}

  @typedoc "Bought scores, keyed by ability."
  @type scores :: %{Srd.Rules.Ability.t() => pos_integer()}

  @doc """
  Points available.

      iex> Srd.Rules.PointBuy.budget()
      27
  """
  @spec budget() :: pos_integer()
  def budget, do: @budget

  @doc """
  The cheapest score that can be bought.

      iex> Srd.Rules.PointBuy.min_score()
      8
  """
  @spec min_score() :: pos_integer()
  def min_score, do: @min

  @doc """
  The highest score that can be bought, before species and background.

      iex> Srd.Rules.PointBuy.max_score()
      15
  """
  @spec max_score() :: pos_integer()
  def max_score, do: @max

  @doc """
  Every score that can be bought, cheapest first.

      iex> Srd.Rules.PointBuy.scores()
      [8, 9, 10, 11, 12, 13, 14, 15]
  """
  @spec scores() :: [pos_integer()]
  def scores, do: Enum.to_list(@min..@max)

  @doc """
  What one score costs, or `:error` if it cannot be bought at all.

      iex> Srd.Rules.PointBuy.cost(8)
      {:ok, 0}

      iex> Srd.Rules.PointBuy.cost(15)
      {:ok, 9}

      iex> Srd.Rules.PointBuy.cost(16)
      :error
  """
  @spec cost(term()) :: {:ok, non_neg_integer()} | :error
  def cost(score), do: Map.fetch(@costs, score)

  @doc """
  What one score costs, assuming it is buyable.

      iex> Srd.Rules.PointBuy.cost!(14)
      7
  """
  @spec cost!(pos_integer()) :: non_neg_integer()
  def cost!(score) do
    case cost(score) do
      {:ok, points} -> points
      :error -> raise ArgumentError, "#{inspect(score)} is not a buyable score"
    end
  end

  @doc """
  What a whole spread costs. Unbuyable scores make the total `:error` rather
  than silently counting as free.

      iex> Srd.Rules.PointBuy.total_cost(%{str: 8, dex: 14, con: 14, int: 8, wis: 8, cha: 8})
      {:ok, 14}

      iex> Srd.Rules.PointBuy.total_cost(%{str: 18})
      :error
  """
  @spec total_cost(map()) :: {:ok, non_neg_integer()} | :error
  def total_cost(scores) when is_map(scores) do
    Enum.reduce_while(scores, {:ok, 0}, fn {_ability, score}, {:ok, sum} ->
      case cost(score) do
        {:ok, points} -> {:cont, {:ok, sum + points}}
        :error -> {:halt, :error}
      end
    end)
  end

  @doc """
  Points left over. `:error` if the spread is not buyable at all.

      iex> Srd.Rules.PointBuy.remaining(%{str: 8, dex: 14, con: 14, int: 8, wis: 8, cha: 8})
      {:ok, 13}
  """
  @spec remaining(map()) :: {:ok, integer()} | :error
  def remaining(scores) do
    case total_cost(scores) do
      {:ok, spent} -> {:ok, @budget - spent}
      :error -> :error
    end
  end

  @doc """
  Whether a spread is one the rules allow: every ability present, every score
  buyable, and the total within budget.

  Spending less than the budget is allowed. It is a waste, not a violation.

      iex> Srd.Rules.PointBuy.legal?(%{str: 15, dex: 14, con: 13, int: 12, wis: 10, cha: 8})
      true

      iex> Srd.Rules.PointBuy.legal?(%{str: 15, dex: 15, con: 15, int: 15, wis: 15, cha: 15})
      false

      iex> Srd.Rules.PointBuy.legal?(%{str: 15})
      false
  """
  @spec legal?(map()) :: boolean()
  def legal?(scores) when is_map(scores) do
    with true <- Enum.sort(Map.keys(scores)) == Enum.sort(Srd.Rules.Ability.all()),
         {:ok, spent} <- total_cost(scores) do
      spent <= @budget
    else
      _ -> false
    end
  end

  def legal?(_), do: false

  @doc """
  Whether every point has been spent.

      iex> Srd.Rules.PointBuy.fully_spent?(%{str: 15, dex: 14, con: 13, int: 12, wis: 10, cha: 8})
      true
  """
  @spec fully_spent?(map()) :: boolean()
  def fully_spent?(scores), do: legal?(scores) and remaining(scores) == {:ok, 0}

  @doc """
  Whether one ability can go up: it is below the ceiling and the next step is
  affordable out of what is left.

      iex> spread = %{str: 8, dex: 8, con: 8, int: 8, wis: 8, cha: 8}
      iex> Srd.Rules.PointBuy.can_increase?(spread, :str)
      true

      iex> maxed = %{str: 15, dex: 14, con: 13, int: 12, wis: 10, cha: 8}
      iex> Srd.Rules.PointBuy.can_increase?(maxed, :cha)
      false
  """
  @spec can_increase?(map(), atom()) :: boolean()
  def can_increase?(scores, ability) do
    with {:ok, score} <- Map.fetch(scores, ability),
         true <- score < @max,
         {:ok, left} <- remaining(scores) do
      cost!(score + 1) - cost!(score) <= left
    else
      _ -> false
    end
  end

  @doc """
  Whether one ability can go down, which is only ever a question of the floor.

      iex> Srd.Rules.PointBuy.can_decrease?(%{str: 9}, :str)
      true

      iex> Srd.Rules.PointBuy.can_decrease?(%{str: 8}, :str)
      false
  """
  @spec can_decrease?(map(), atom()) :: boolean()
  def can_decrease?(scores, ability) do
    case Map.fetch(scores, ability) do
      {:ok, score} -> score > @min
      :error -> false
    end
  end
end
