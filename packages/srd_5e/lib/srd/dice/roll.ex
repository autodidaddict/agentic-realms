defmodule Srd.Dice.Roll do
  @moduledoc """
  An immutable representation of a completed roll.
  """
  @enforce_keys [:count, :sides, :dice, :total]
  defstruct count: 1, sides: nil, modifier: 0, dice: [], reduce: :sum, total: nil

  @typedoc """
  Represents the immutable result of a completed roll of dice. This is only
  ever used to represent a single type of die. Rolling a d20 and a d10 is two
  rolls while 2d10+3 is a single roll.

  ## Fields
  * `:count` - The number of times the die was rolled
  * `:sides` - The number of sides on the die
  * `:modifier` - A flat modifier applied to the die roll value after calculation
  * `:dice` - A list containing the raw value for each die roll. Occasionally needed for criticals, etc
  * `:reduce` - Indicates what function to run on the die rolls, e.g. sum (default), max, min, drop-lowest, etc
  * `:total` - The final result of the role. In most cases, this is the value used for rule resolution
  """
  @type t :: %__MODULE__{
          count: pos_integer(),
          sides: non_neg_integer(),
          modifier: integer(),
          dice: [pos_integer()],
          reduce: :sum | :min | :max | :drop_lowest,
          total: integer()
        }
end
