defmodule Srd.Rules.Initiative do
  @moduledoc """
  Initiative ordering.
  """
  alias Srd.Dice.Roll

  @typedoc "A combatant identifier paired with its initiative roll."
  @type entry :: {term(), Roll.t()}

  @doc """
  The modifier added to an initiative roll: the Dexterity modifier.

  A named function rather than the caller reaching for `dex_modifier` directly,
  because features change what goes here — the Alert feat adds the proficiency
  bonus — and they should change it in one place.

      iex> Srd.Rules.Initiative.modifier(3)
      3
  """
  @spec modifier(integer()) :: integer()
  def modifier(dex_modifier) when is_integer(dex_modifier), do: dex_modifier

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
