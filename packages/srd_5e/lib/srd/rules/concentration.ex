defmodule Srd.Rules.Concentration do
  @moduledoc """
  Concentration.
  """

  @doc """
  The Constitution saving throw DC to maintain concentration after taking
  `damage`: the greater of 10 and half the damage, rounded down.
  """
  @spec save_dc(non_neg_integer()) :: pos_integer()
  def save_dc(damage) when is_integer(damage) and damage >= 0 do
    max(10, div(damage, 2))
  end
end
