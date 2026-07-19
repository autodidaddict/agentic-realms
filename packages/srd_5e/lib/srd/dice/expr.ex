defmodule Srd.Dice.Expr do
  @moduledoc """
  A parsed, unrolled dice expression. A dice expression can be built
    manually or can be parsed from human-readable dice notation like d20, 2d4+1, etc.
  """
  @enforce_keys [:count, :sides]
  defstruct count: 1, sides: nil, modifier: 0

  @type t :: %__MODULE__{count: pos_integer(), sides: pos_integer(), modifier: integer()}

  #        NdX            ±M (optional)
  @dice_notation ~r/^(\d*)d(\d+)(?:([+-])(\d+))?$/i

  @spec parse(String.t() | t()) :: {:ok, t()} | {:error, {:invalid_dice, String.t()}}

  # already parsed → pass through
  def parse(%__MODULE__{} = expr), do: {:ok, expr}

  def parse(string) when is_binary(string) do
    case Regex.run(@dice_notation, String.trim(string), capture: :all_but_first) do
      [count, sides, sign, mod] -> build(count, sides, sign, mod, string)
      # :re drops trailing non-participating groups, so a modifier-less roll
      # comes back as just [count, sides].
      [count, sides] -> build(count, sides, "", "", string)
      _ -> {:error, {:invalid_dice, string}}
    end
  end

  @spec parse!(String.t() | t()) :: t()
  def parse!(input) do
    case parse(input) do
      {:ok, expr} -> expr
      {:error, {:invalid_dice, s}} -> raise ArgumentError, "invalid dice notation: #{inspect(s)}"
    end
  end

  defp build(count, sides, sign, mod, original) do
    # "d20" → 1d20
    count = if count == "", do: 1, else: String.to_integer(count)
    sides = String.to_integer(sides)

    modifier =
      case mod do
        "" -> 0
        m -> String.to_integer(m) * if(sign == "-", do: -1, else: 1)
      end

    if count >= 1 and sides >= 1 do
      {:ok, %__MODULE__{count: count, sides: sides, modifier: modifier}}
    else
      {:error, {:invalid_dice, original}}
    end
  end
end
