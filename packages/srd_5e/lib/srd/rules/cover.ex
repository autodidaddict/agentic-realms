defmodule Srd.Rules.Cover do
  @moduledoc """
  Cover.
  """

  @typedoc "A degree of cover."
  @type cover :: :none | :half | :three_quarters | :total

  @doc """
  The bonus a degree of cover grants to Armor Class and Dexterity saving throws.

  Total cover can't be targeted at all, so it returns `:cannot_target`.
  """
  @spec bonus(cover()) :: 0 | 2 | 5 | :cannot_target
  def bonus(:none), do: 0
  def bonus(:half), do: 2
  def bonus(:three_quarters), do: 5
  def bonus(:total), do: :cannot_target
end
