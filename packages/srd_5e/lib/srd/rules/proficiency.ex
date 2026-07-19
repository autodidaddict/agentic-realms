defmodule Srd.Rules.Proficiency do
  @moduledoc """
  Proficiency bonus.
  """

  @doc """
  The proficiency bonus for a character level: +2 at levels 1 through 4, rising
  by 1 every four levels.
  """
  @spec bonus(pos_integer()) :: pos_integer()
  def bonus(level) when is_integer(level) and level >= 1 do
    2 + div(level - 1, 4)
  end

  @doc """
  The proficiency bonus for a monster's Challenge Rating: +2 through CR 4
  (including fractional CRs), rising by 1 every four CR above that.
  """
  @spec bonus_for_cr(number()) :: pos_integer()
  def bonus_for_cr(cr) when is_number(cr) and cr <= 4, do: 2
  def bonus_for_cr(cr) when is_number(cr), do: 2 + div(trunc(cr) - 1, 4)
end
