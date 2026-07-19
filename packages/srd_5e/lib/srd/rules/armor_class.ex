defmodule Srd.Rules.ArmorClass do
  @moduledoc """
  Armor Class computation.
  """

  @doc """
  Compute an Armor Class from worn armor and a Dexterity modifier.

  Pass `nil` for unarmored (`10 + Dex`). Light armor adds the full Dexterity
  modifier, medium armor caps it at +2, and heavy armor ignores it. A shield,
  passed via the `:shield` option, adds its bonus.

  Armor is any value with `:category` and `:base_ac`, such as a
  `Srd.Content.Armor`.
  """
  @spec compute(map() | nil, integer(), keyword()) :: integer()
  def compute(armor, dex_modifier, opts \\ []) do
    base_ac(armor, dex_modifier) + shield_bonus(Keyword.get(opts, :shield))
  end

  defp base_ac(nil, dex), do: 10 + dex
  defp base_ac(%{category: :light, base_ac: base}, dex), do: base + dex
  defp base_ac(%{category: :medium, base_ac: base}, dex), do: base + min(dex, 2)
  defp base_ac(%{category: :heavy, base_ac: base}, _dex), do: base

  defp base_ac(%{category: :shield}, _dex),
    do: raise(ArgumentError, "a shield is worn via the :shield option, not as armor")

  defp shield_bonus(nil), do: 0
  defp shield_bonus(%{category: :shield, base_ac: bonus}), do: bonus

  defp shield_bonus(%{category: category}),
    do:
      raise(ArgumentError, "the :shield option must be a shield, got #{inspect(category)} armor")
end
