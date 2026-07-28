defmodule Srd.Rules.Ability do
  @moduledoc """
  The six abilities and the math over their scores.
  """

  @abilities [
    {:str, "Strength"},
    {:dex, "Dexterity"},
    {:con, "Constitution"},
    {:int, "Intelligence"},
    {:wis, "Wisdom"},
    {:cha, "Charisma"}
  ]

  @standard_array [15, 14, 13, 12, 10, 8]

  @typedoc "One of the six abilities."
  @type t :: :str | :dex | :con | :int | :wis | :cha

  @doc """
  The ability modifier for a score: `score - 10`, halved and rounded down.
  """
  @spec modifier(pos_integer()) :: integer()
  def modifier(score) when is_integer(score) do
    Integer.floor_div(score - 10, 2)
  end

  @doc """
  The six abilities in the order the SRD lists them. Character sheets are
  expected to present them this way, so the order is part of the contract.

      iex> Srd.Rules.Ability.all()
      [:str, :dex, :con, :int, :wis, :cha]
  """
  @spec all() :: [t()]
  def all, do: Enum.map(@abilities, &elem(&1, 0))

  @doc """
  The display name of an ability.

      iex> Srd.Rules.Ability.name(:cha)
      "Charisma"
  """
  @spec name(t()) :: String.t()
  for {ability, name} <- @abilities do
    def name(unquote(ability)), do: unquote(name)
  end

  def name(other), do: raise(ArgumentError, "unknown ability: #{inspect(other)}")

  @doc """
  The standard array: the six scores the SRD offers in place of rolling, highest
  first. Which ability takes which score is the character's choice, so this is a
  list rather than a map.

      iex> Srd.Rules.Ability.standard_array()
      [15, 14, 13, 12, 10, 8]
  """
  @spec standard_array() :: [pos_integer()]
  def standard_array, do: @standard_array
end
