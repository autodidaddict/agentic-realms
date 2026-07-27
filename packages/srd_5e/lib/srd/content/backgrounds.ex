defmodule Srd.Content.Backgrounds do
  @moduledoc """
  SRD backgrounds, looked up by slug.

  Each background's origin feat is checked against `Srd.Content.Feats` while
  compiling, so the reference is known to be a real origin feat.
  """
  alias Srd.Content.Background
  alias Srd.Content.Feats

  @data_file Path.expand("../../../priv/data/backgrounds.exs", __DIR__)
  @external_resource @data_file

  @backgrounds @data_file
               |> Code.eval_file()
               |> elem(0)
               |> Map.new(fn data -> {data.slug, Background.new(data)} end)

  for {slug, background} <- @backgrounds do
    case Feats.get(background.origin_feat) do
      nil ->
        raise ArgumentError,
              "#{slug} grants unknown feat #{inspect(background.origin_feat)}"

      %{category: :origin} ->
        :ok

      feat ->
        raise ArgumentError, "#{slug} grants #{feat.slug}, which is not an origin feat"
    end
  end

  @doc """
  Every background.
  """
  @spec all() :: [Background.t()]
  def all, do: Map.values(backgrounds())

  @doc """
  Every background matching the given filters.

  Supported filters: `:skill` (backgrounds granting proficiency in that skill)
  and `:ability` (backgrounds that can raise that ability).

      iex> Srd.Content.Backgrounds.all(ability: :int) |> Enum.map(& &1.slug) |> Enum.sort()
      ["acolyte", "criminal", "sage"]
  """
  @spec all(keyword()) :: [Background.t()]
  def all(filters) do
    Enum.filter(all(), fn background ->
      Enum.all?(filters, fn
        {:skill, skill} -> skill in background.skills
        {:ability, ability} -> ability in background.ability_scores
        {key, _} -> raise ArgumentError, "unknown background filter: #{inspect(key)}"
      end)
    end)
  end

  @doc """
  Look up a background by slug, returning `nil` if there is none.
  """
  @spec get(String.t()) :: Background.t() | nil
  def get(slug), do: Map.get(backgrounds(), slug)

  @doc """
  Look up a background by slug, raising if there is none.
  """
  @spec fetch!(String.t()) :: Background.t()
  def fetch!(slug) do
    case get(slug) do
      nil -> raise KeyError, "no background with slug #{inspect(slug)}"
      background -> background
    end
  end

  defp backgrounds, do: @backgrounds
end
