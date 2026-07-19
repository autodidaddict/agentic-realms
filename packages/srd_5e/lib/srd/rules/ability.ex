defmodule Srd.Rules.Ability do
  @moduledoc """
  Ability score math.
  """

  @doc """
  The ability modifier for a score: `score - 10`, halved and rounded down.
  """
  @spec modifier(pos_integer()) :: integer()
  def modifier(score) when is_integer(score) do
    Integer.floor_div(score - 10, 2)
  end
end
