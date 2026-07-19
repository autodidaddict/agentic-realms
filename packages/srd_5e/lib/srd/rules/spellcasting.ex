defmodule Srd.Rules.Spellcasting do
  @moduledoc """
  Spellcasting math.
  """

  @doc """
  A spellcaster's save DC: `8 + proficiency bonus + spellcasting ability modifier`.
  """
  @spec save_dc(integer(), integer()) :: integer()
  def save_dc(proficiency, ability_modifier) do
    8 + proficiency + ability_modifier
  end

  @doc """
  A spellcaster's spell attack bonus: `proficiency bonus + spellcasting ability modifier`.
  """
  @spec attack_bonus(integer(), integer()) :: integer()
  def attack_bonus(proficiency, ability_modifier) do
    proficiency + ability_modifier
  end
end
