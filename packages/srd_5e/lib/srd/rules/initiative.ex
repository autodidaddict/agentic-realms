defmodule Srd.Rules.Initiative do
  @moduledoc """
  Initiative ordering.
  """
  alias Srd.Dice.Roll

  @typedoc "A combatant identifier paired with its initiative roll."
  @type entry :: {term(), Roll.t()}

  @doc """
  Order combatants by their initiative rolls, highest total first.

  Ties keep their input order, so a caller can break ties by sorting the input
  by its own tiebreaker first; a stable sort preserves that order within a tie.
  """
  @spec order([entry()]) :: [entry()]
  def order(entries) do
    Enum.sort_by(entries, fn {_id, %Roll{} = roll} -> roll.total end, :desc)
  end
end
