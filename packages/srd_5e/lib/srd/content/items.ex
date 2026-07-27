defmodule Srd.Content.Items do
  @moduledoc """
  SRD items, looked up by slug.

  Every pack's contents are checked against this list while compiling, so a
  mistyped slug is a build failure rather than a missing item at runtime.
  """
  alias Srd.Content.Item

  @data_file Path.expand("../../../priv/data/items.exs", __DIR__)
  @external_resource @data_file

  @items @data_file
         |> Code.eval_file()
         |> elem(0)
         |> Map.new(fn data -> {data.slug, Item.new(data)} end)

  for {slug, item} <- @items, entry <- item.contents do
    unless Map.has_key?(@items, entry.item) do
      raise ArgumentError, "#{slug} contains unknown item #{inspect(entry.item)}"
    end
  end

  @doc """
  Every item.
  """
  @spec all() :: [Item.t()]
  def all, do: Map.values(items())

  @doc """
  Every item matching the given filters.

  Supported filters: `:category`.

      iex> Srd.Content.Items.all(category: :gaming_set) |> length()
      4
  """
  @spec all(keyword()) :: [Item.t()]
  def all(filters) do
    Enum.filter(all(), fn item ->
      Enum.all?(filters, fn
        {:category, category} -> item.category == category
        {key, _} -> raise ArgumentError, "unknown item filter: #{inspect(key)}"
      end)
    end)
  end

  @doc """
  The slugs of every item in a category, sorted.

      iex> Srd.Content.Items.slugs(:gaming_set)
      ["dice-set", "dragonchess-set", "playing-card-set", "three-dragon-ante-set"]
  """
  @spec slugs(Item.category()) :: [String.t()]
  def slugs(category) do
    [category: category] |> all() |> Enum.map(& &1.slug) |> Enum.sort()
  end

  @doc """
  Look up an item by slug, returning `nil` if there is none.
  """
  @spec get(String.t()) :: Item.t() | nil
  def get(slug), do: Map.get(items(), slug)

  @doc """
  Look up an item by slug, raising if there is none.
  """
  @spec fetch!(String.t()) :: Item.t()
  def fetch!(slug) do
    case get(slug) do
      nil -> raise KeyError, "no item with slug #{inspect(slug)}"
      item -> item
    end
  end

  defp items, do: @items
end
