defmodule Srd.Rules.Rest do
  @moduledoc """
  Rest and Hit Dice recovery.
  """

  @doc """
  The number of spent Hit Dice a creature regains on a long rest: half its total,
  rounded down, with a minimum of one.
  """
  @spec hit_dice_regained(pos_integer()) :: pos_integer()
  def hit_dice_regained(total) when is_integer(total) and total >= 1 do
    max(1, div(total, 2))
  end

  @doc """
  The hit points regained from spending one Hit Die on a short rest: the die roll
  plus the Constitution modifier, with a minimum of 0.
  """
  @spec hit_die_healing(pos_integer(), integer()) :: non_neg_integer()
  def hit_die_healing(die_roll, con_modifier)
      when is_integer(die_roll) and die_roll >= 1 and is_integer(con_modifier) do
    max(die_roll + con_modifier, 0)
  end
end
