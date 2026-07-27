defmodule Srd.Content.Feats do
  @moduledoc """
  SRD feats, looked up by slug.

  Feats are the one content type whose availability depends on the character, so
  this is where the filtering goes beyond naming a field: `eligible/1` takes
  facts about a character and returns the feats they qualify for.
  """
  alias Srd.Content.Feat

  @data_file Path.expand("../../../priv/data/feats.exs", __DIR__)
  @external_resource @data_file

  @feats @data_file
         |> Code.eval_file()
         |> elem(0)
         |> Map.new(fn data -> {data.slug, Feat.new(data)} end)

  @doc """
  Every feat.
  """
  @spec all() :: [Feat.t()]
  def all, do: Map.values(feats())

  @doc """
  Every feat matching the given filters.

  Supported filters: `:category` and `:repeatable?`.

      iex> Srd.Content.Feats.all(category: :origin) |> Enum.map(& &1.slug) |> Enum.sort()
      ["alert", "magic-initiate", "savage-attacker", "skilled"]
  """
  @spec all(keyword()) :: [Feat.t()]
  def all(filters) do
    Enum.filter(all(), fn feat ->
      Enum.all?(filters, fn
        {:category, category} -> feat.category == category
        {:repeatable?, repeatable?} -> feat.repeatable? == repeatable?
        {key, _} -> raise ArgumentError, "unknown feat filter: #{inspect(key)}"
      end)
    end)
  end

  @doc """
  The slugs of every feat in a category, sorted.

      iex> Srd.Content.Feats.slugs(:fighting_style)
      ["archery", "defense", "great-weapon-fighting", "two-weapon-fighting"]
  """
  @spec slugs(Feat.category()) :: [String.t()]
  def slugs(category) do
    [category: category] |> all() |> Enum.map(& &1.slug) |> Enum.sort()
  end

  @doc """
  Every feat a character qualifies for.

  Takes the same facts as `Srd.Content.Feat.meets?/2` - `:level`, `:abilities`,
  and `:features` - plus an optional `:category` to narrow the result. Nothing
  about the character is held here; the caller passes what it knows.

      iex> Srd.Content.Feats.eligible(level: 1) |> Enum.map(& &1.slug) |> Enum.sort()
      ["alert", "magic-initiate", "savage-attacker", "skilled"]

      iex> Srd.Content.Feats.eligible(level: 4, abilities: %{str: 13})
      ...> |> Enum.map(& &1.slug) |> Enum.sort()
      ["ability-score-improvement", "alert", "grappler", "magic-initiate",
       "savage-attacker", "skilled"]
  """
  @spec eligible(keyword()) :: [Feat.t()]
  def eligible(character \\ []) do
    {category, character} = Keyword.pop(character, :category)

    all()
    |> then(fn feats ->
      if category, do: Enum.filter(feats, &(&1.category == category)), else: feats
    end)
    |> Enum.filter(&Feat.meets?(&1, character))
  end

  @doc """
  Look up a feat by slug, returning `nil` if there is none.
  """
  @spec get(String.t()) :: Feat.t() | nil
  def get(slug), do: Map.get(feats(), slug)

  @doc """
  Look up a feat by slug, raising if there is none.
  """
  @spec fetch!(String.t()) :: Feat.t()
  def fetch!(slug) do
    case get(slug) do
      nil -> raise KeyError, "no feat with slug #{inspect(slug)}"
      feat -> feat
    end
  end

  defp feats, do: @feats
end
