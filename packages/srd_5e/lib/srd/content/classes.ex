defmodule Srd.Content.Classes do
  @moduledoc """
  SRD classes, looked up by slug.
  """
  alias Srd.Content.Class

  @data_file Path.expand("../../../priv/data/classes.exs", __DIR__)
  @external_resource @data_file

  @classes @data_file
           |> Code.eval_file()
           |> elem(0)
           |> Map.new(fn data -> {data.slug, Class.new(data)} end)

  @doc """
  Every class.
  """
  @spec all() :: [Class.t()]
  def all, do: Map.values(classes())

  @doc """
  Every class matching the given filters.

  Supported filters: `:spellcasting?`, `:ability` (classes whose primary ability
  includes it), `:skill` (classes offering proficiency in it), and
  `:armor_training`.

      iex> Srd.Content.Classes.all(spellcasting?: false)
      ...> |> Enum.map(& &1.slug) |> Enum.sort()
      ["barbarian", "fighter", "monk", "rogue"]
  """
  @spec all(keyword()) :: [Class.t()]
  def all(filters) do
    Enum.filter(all(), fn class ->
      Enum.all?(filters, fn
        {:spellcasting?, true} -> class.spellcasting != nil
        {:spellcasting?, false} -> class.spellcasting == nil
        {:ability, ability} -> ability in elem(class.primary_ability, 1)
        {:skill, skill} -> skill in class.skill_choice.from
        {:armor_training, armor} -> armor in class.armor_training
        {key, _} -> raise ArgumentError, "unknown class filter: #{inspect(key)}"
      end)
    end)
  end

  @doc """
  The classes a character with these ability scores could multiclass into.

  The SRD asks for a 13 in the primary ability of the new class and of every
  class the character already has, so this answers the first half; the caller
  knows the classes the character already holds.

      iex> Srd.Content.Classes.multiclass_options(%{str: 15, cha: 13})
      ...> |> Enum.map(& &1.slug) |> Enum.sort()
      ["barbarian", "bard", "fighter", "paladin", "sorcerer", "warlock"]
  """
  @spec multiclass_options(map()) :: [Class.t()]
  def multiclass_options(scores) do
    Enum.filter(all(), &Class.primary_ability_met?(&1, scores))
  end

  @doc """
  Look up a class by slug, returning `nil` if there is none.
  """
  @spec get(String.t()) :: Class.t() | nil
  def get(slug), do: Map.get(classes(), slug)

  @doc """
  Look up a class by slug, raising if there is none.
  """
  @spec fetch!(String.t()) :: Class.t()
  def fetch!(slug) do
    case get(slug) do
      nil -> raise KeyError, "no class with slug #{inspect(slug)}"
      class -> class
    end
  end

  defp classes, do: @classes
end
