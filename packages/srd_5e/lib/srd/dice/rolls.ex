defmodule Srd.Dice.Rolls do
  @moduledoc """
  The SRD's standard rolls, named by intent.

  Every function here returns a `Srd.Dice.Roll` and applies no meaning
  to the roll. These are convenience functions so developers don't have
  to memorize the SRD rules for dice rolling.
  """
  alias Srd.Dice

  @doc "An attack roll: **1d20** + _bonus_ (2d20 keep highest/lowest under advantage)."
  @spec attack(integer(), keyword()) :: Dice.Roll.t()
  def attack(bonus, opts \\ []), do: Dice.d20(bonus, opts)

  @doc "An ability check: **1d20** + _modifier_."
  @spec check(integer(), keyword()) :: Dice.Roll.t()
  def check(modifier, opts \\ []), do: Dice.d20(modifier, opts)

  @doc "A saving throw: **1d20** + _bonus_."
  @spec save(integer(), keyword()) :: Dice.Roll.t()
  def save(bonus, opts \\ []), do: Dice.d20(bonus, opts)

  @doc "An initiative roll: **1d20** + _Dex modifier_."
  @spec initiative(integer(), keyword()) :: Dice.Roll.t()
  def initiative(dex_mod, opts \\ []), do: Dice.d20(dex_mod, opts)

  @doc "A death saving throw: **1d20**, no modifier."
  @spec death_save() :: Dice.Roll.t()
  def death_save, do: Dice.d20(0)

  @doc "An ability score: **4d6**, drop the lowest."
  @spec ability_score() :: Dice.Roll.t()
  def ability_score, do: Dice.roll("4d6", reduce: :drop_lowest)
end
