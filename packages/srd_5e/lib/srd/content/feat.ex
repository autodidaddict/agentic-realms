defmodule Srd.Content.Feat do
  @moduledoc """
  An SRD feat.

  Prerequisites are data rather than prose, so a caller can ask whether a
  character qualifies without parsing anything. See `Srd.Content.Feats.eligible/1`.
  """
  alias Srd.Content.Feature

  @categories ~w(origin general fighting_style epic_boon)a
  @abilities ~w(str dex con int wis cha)a

  @enforce_keys [:slug, :name, :category]
  defstruct [:slug, :name, :category, prerequisites: [], features: [], repeatable?: false]

  @typedoc "The category a feat belongs to."
  @type category :: :origin | :general | :fighting_style | :epic_boon

  @typedoc """
  A prerequisite a character must meet to take the feat:

  * `{:level, n}` - character level `n` or higher
  * `{:ability, abilities, score}` - `score` or higher in any one of `abilities`
  * `{:feature, name}` - a feature the character already has, such as
    `:fighting_style` or `:spellcasting`
  """
  @type prerequisite ::
          {:level, pos_integer()}
          | {:ability, [atom()], pos_integer()}
          | {:feature, atom()}

  @typedoc """
  An SRD feat:

  * `:slug` - stable identifier used for lookup
  * `:name` - display name
  * `:category` - origin, general, fighting style, or epic boon
  * `:prerequisites` - what a character must have to take it
  * `:features` - the benefits it grants
  * `:repeatable?` - whether it can be taken more than once
  """
  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          category: category(),
          prerequisites: [prerequisite()],
          features: [Feature.t()],
          repeatable?: boolean()
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      slug: data.slug,
      name: data.name,
      category: validate_category!(data.category),
      prerequisites: Enum.map(data[:prerequisites] || [], &validate_prerequisite!/1),
      features: Enum.map(data[:features] || [], &Feature.new/1),
      repeatable?: data[:repeatable?] || false
    }
  end

  @doc """
  Whether a character meets every prerequisite of the feat.

  Facts about the character are passed in: `:level`, `:abilities` (a map of
  ability to score), and `:features` (the features the character already has).
  Anything not passed is treated as absent, so a bare call answers for a level 1
  character with nothing.

      iex> Srd.Content.Feats.get("grappler")
      ...> |> Srd.Content.Feat.meets?(level: 4, abilities: %{str: 15})
      true

      iex> Srd.Content.Feats.get("grappler") |> Srd.Content.Feat.meets?(level: 4)
      false
  """
  @spec meets?(t(), keyword()) :: boolean()
  def meets?(%__MODULE__{prerequisites: prerequisites}, character \\ []) do
    level = Keyword.get(character, :level, 1)
    abilities = Keyword.get(character, :abilities, %{})
    features = Keyword.get(character, :features, [])

    Enum.all?(prerequisites, fn
      {:level, required} -> level >= required
      {:ability, allowed, score} -> Enum.any?(allowed, &(Map.get(abilities, &1, 0) >= score))
      {:feature, feature} -> feature in features
    end)
  end

  defp validate_category!(category) when category in @categories, do: category

  defp validate_category!(category),
    do: raise(ArgumentError, "unknown feat category: #{inspect(category)}")

  defp validate_prerequisite!({:level, level} = prerequisite)
       when is_integer(level) and level > 0,
       do: prerequisite

  defp validate_prerequisite!({:ability, abilities, score} = prerequisite)
       when is_list(abilities) and is_integer(score) do
    Enum.each(abilities, fn ability ->
      unless ability in @abilities do
        raise ArgumentError, "unknown ability: #{inspect(ability)}"
      end
    end)

    prerequisite
  end

  defp validate_prerequisite!({:feature, feature} = prerequisite) when is_atom(feature),
    do: prerequisite

  defp validate_prerequisite!(prerequisite),
    do: raise(ArgumentError, "unknown prerequisite: #{inspect(prerequisite)}")
end
