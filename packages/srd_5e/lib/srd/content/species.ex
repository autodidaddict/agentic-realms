defmodule Srd.Content.Species do
  @moduledoc """
  SRD species, looked up by slug.

  Species is the whole of the sub-tier. The 2024 rules have no subraces: where a
  species offers a further choice, it is a trait of that species, named in
  `:lineage_trait`, with its options in `:lineages`. Dwarves, halflings, humans,
  and orcs offer nothing at that tier, so their `:lineages` is empty.

  Species is also the one content type whose plural is the same word, so the
  struct and its lookups share a module rather than inventing a name for the
  collection. A module can't build its own struct while compiling, so the data
  itself is loaded by `Srd.Content.Species.Data` behind this one.
  """
  alias Srd.Content.Feature
  alias Srd.Content.Lineage
  alias Srd.Content.Species.Data

  @enforce_keys [:slug, :name, :sizes, :speed]
  defstruct [:slug, :name, :sizes, :speed, :lineage_trait, features: [], lineages: []]

  @typedoc "A creature size."
  @type size :: :tiny | :small | :medium | :large | :huge | :gargantuan

  @typedoc """
  An SRD species:

  * `:slug` - stable identifier used for lookup
  * `:name` - display name
  * `:sizes` - the sizes it can be; more than one means the player chooses
  * `:speed` - its walking speed in feet
  * `:lineage_trait` - the trait that offers the lineage choice, or `nil`
  * `:features` - the traits it grants, by level
  * `:lineages` - the options its lineage trait offers, empty when it has none
  """
  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          sizes: [size()],
          speed: pos_integer(),
          lineage_trait: String.t() | nil,
          features: [Feature.t()],
          lineages: [Lineage.t()]
        }

  @doc """
  Every species.
  """
  @spec all() :: [t()]
  def all, do: Data.all()

  @doc """
  Every species matching the given filters.

  Supported filters: `:size`, `:speed`, and `:lineages?` (whether the species
  offers a lineage choice).

      iex> Srd.Content.Species.all(lineages?: false) |> Enum.map(& &1.slug) |> Enum.sort()
      ["dwarf", "halfling", "human", "orc"]
  """
  @spec all(keyword()) :: [t()]
  def all(filters) do
    Enum.filter(all(), fn species ->
      Enum.all?(filters, fn
        {:size, size} -> size in species.sizes
        {:speed, speed} -> species.speed == speed
        {:lineages?, true} -> species.lineages != []
        {:lineages?, false} -> species.lineages == []
        {key, _} -> raise ArgumentError, "unknown species filter: #{inspect(key)}"
      end)
    end)
  end

  @doc """
  Look up a species by slug, returning `nil` if there is none.
  """
  @spec get(String.t()) :: t() | nil
  def get(slug), do: Data.get(slug)

  @doc """
  Look up a species by slug, raising if there is none.
  """
  @spec fetch!(String.t()) :: t()
  def fetch!(slug) do
    case get(slug) do
      nil -> raise KeyError, "no species with slug #{inspect(slug)}"
      species -> species
    end
  end

  @doc """
  A species' lineage by slug, returning `nil` if the species has no such
  lineage.

      iex> Srd.Content.Species.lineage("elf", "wood-elf").name
      "Wood Elf"

      iex> Srd.Content.Species.lineage("dwarf", "wood-elf")
      nil
  """
  @spec lineage(String.t() | t(), String.t()) :: Lineage.t() | nil
  def lineage(slug, lineage_slug) when is_binary(slug) do
    case get(slug) do
      nil -> nil
      species -> lineage(species, lineage_slug)
    end
  end

  def lineage(%__MODULE__{lineages: lineages}, lineage_slug) do
    Enum.find(lineages, &(&1.slug == lineage_slug))
  end
end
