defmodule Srd.Content.Species.Data do
  @moduledoc false
  alias Srd.Content.Feature
  alias Srd.Content.Lineage
  alias Srd.Content.Species

  @sizes ~w(tiny small medium large huge gargantuan)a

  @data_file Path.expand("../../../../priv/data/species.exs", __DIR__)
  @external_resource @data_file

  @species @data_file
           |> Code.eval_file()
           |> elem(0)
           |> Map.new(fn data ->
             {data.slug,
              %Species{
                slug: data.slug,
                name: data.name,
                sizes: data.sizes,
                speed: data.speed,
                lineage_trait: data[:lineage_trait],
                features: Enum.map(data[:features] || [], &Feature.new/1),
                lineages: Enum.map(data[:lineages] || [], &Lineage.new/1)
              }}
           end)

  for {slug, species} <- @species do
    Enum.each(species.sizes, fn size ->
      unless size in @sizes do
        raise ArgumentError, "#{slug} has unknown size #{inspect(size)}"
      end
    end)

    case {species.lineage_trait, species.lineages} do
      {nil, []} ->
        :ok

      {nil, _lineages} ->
        raise ArgumentError, "#{slug} has lineages but does not name the trait offering them"

      {trait, []} ->
        raise ArgumentError, "#{slug}'s #{trait} offers no lineages"

      {_trait, _lineages} ->
        :ok
    end
  end

  @spec all() :: [Species.t()]
  def all, do: Map.values(@species)

  @spec get(String.t()) :: Species.t() | nil
  def get(slug), do: Map.get(@species, slug)
end
