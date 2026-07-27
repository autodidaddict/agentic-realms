defmodule Srd.Content.Armors do
  @moduledoc """
  SRD armor, looked up by slug.
  """
  alias Srd.Content.Armor

  @data_file Path.expand("../../../priv/data/armor.exs", __DIR__)
  @external_resource @data_file

  @armor @data_file
         |> Code.eval_file()
         |> elem(0)
         |> Map.new(fn data -> {data.slug, Armor.new(data)} end)

  @doc """
  Every armor.
  """
  @spec all() :: [Armor.t()]
  def all, do: Map.values(armor())

  @doc """
  Every armor matching the given filters.

  Supported filters: `:category` and `:stealth_disadvantage`.

      iex> Srd.Content.Armors.all(category: :heavy) |> length()
      4
  """
  @spec all(keyword()) :: [Armor.t()]
  def all(filters) do
    Enum.filter(all(), fn armor ->
      Enum.all?(filters, fn
        {:category, category} -> armor.category == category
        {:stealth_disadvantage, value} -> armor.stealth_disadvantage == value
        {key, _} -> raise ArgumentError, "unknown armor filter: #{inspect(key)}"
      end)
    end)
  end

  @doc """
  Look up armor by slug, returning `nil` if there is none.
  """
  @spec get(String.t()) :: Armor.t() | nil
  def get(slug), do: Map.get(armor(), slug)

  @doc """
  Look up armor by slug, raising if there is none.
  """
  @spec fetch!(String.t()) :: Armor.t()
  def fetch!(slug) do
    case get(slug) do
      nil -> raise KeyError, "no armor with slug #{inspect(slug)}"
      armor -> armor
    end
  end

  defp armor, do: @armor
end
