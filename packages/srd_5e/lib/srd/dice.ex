defmodule Srd.Dice do
  @moduledoc """
  Dice rolling for SRD 5.2 resolution.

  """
  alias Srd.Dice.{Expr, Roll}

  @doc """
  Roll a dice expression and return an immutable `Srd.Dice.Roll`.

  Takes a notation string or a parsed `Srd.Dice.Expr`. The `:reduce` option names
  how the dice are combined before the modifier is added. The default is `:sum`

      iex> Srd.Dice.roll("2d6+3")
      %Srd.Dice.Roll{count: 2, sides: 6, modifier: 3, dice: [4, 5], reduce: :sum, total: 12}

      iex> Srd.Dice.roll("2d20", reduce: :max)   # advantage
      %Srd.Dice.Roll{count: 2, sides: 20, modifier: 0, dice: [7, 18], reduce: :max, total: 18}
  """
  @spec roll(String.t() | Expr.t(), keyword()) :: Roll.t()
  def roll(input, opts \\ []) do
    %Expr{count: count, sides: sides, modifier: modifier} = Expr.parse!(input)

    reduce = Keyword.get(opts, :reduce, :sum)

    dice = for _ <- 1..count, do: :rand.uniform(sides)
    total = apply_reduce(reduce, dice) + modifier

    %Roll{
      count: count,
      sides: sides,
      modifier: modifier,
      dice: dice,
      reduce: reduce,
      total: total
    }
  end

  @doc """
  Performs a d20 roll. Options can modify the number of D20s rolled:

  * `:advantage` - Rolls 2d20 and takes the max
  * `:disadvantage` - Rolls 2d20 and takes the min

  Normal behavior is a 1d20.
  """
  def d20(modifier \\ 0, opts \\ []) do
    {count, reduce} =
      case Keyword.get(opts, :advantage, :normal) do
        :advantage -> {2, :max}
        :disadvantage -> {2, :min}
        :normal -> {1, :sum}
      end

    roll(%Expr{count: count, sides: 20, modifier: modifier}, reduce: reduce)
  end

  defp apply_reduce(:sum, dice), do: Enum.sum(dice)
  defp apply_reduce(:max, dice), do: Enum.max(dice)
  defp apply_reduce(:min, dice), do: Enum.min(dice)
  defp apply_reduce(:drop_lowest, dice), do: Enum.sum(dice) - Enum.min(dice)

  defp apply_reduce({:drop_lowest, n}, dice),
    do: dice |> Enum.sort() |> Enum.drop(n) |> Enum.sum()

  defp apply_reduce(tag, _dice), do: raise(ArgumentError, "unknown reduce tag: #{inspect(tag)}")
end
