defmodule Srd.Content.Item do
  @moduledoc """
  An SRD item: a tool, a spellcasting focus, an equipment pack, or a piece of
  adventuring gear.

  This covers what class and background starting equipment refers to, so every
  equipment entry resolves to a slug. Weapons and armor are their own content;
  see `Srd.Content.Weapons` and `Srd.Content.Armors`.
  """

  @categories ~w(artisans_tools focus gaming_set gear musical_instrument pack tool)a
  @abilities ~w(str dex con int wis cha)a

  @enforce_keys [:slug, :name, :category]
  defstruct [:slug, :name, :category, :ability, contents: [], variants: []]

  @typedoc "What kind of item this is."
  @type category ::
          :artisans_tools
          | :focus
          | :gaming_set
          | :gear
          | :musical_instrument
          | :pack
          | :tool

  @typedoc "An entry in a pack: an item slug and how many of it."
  @type entry :: %{item: String.t(), quantity: pos_integer()}

  @typedoc """
  An SRD item:

  * `:slug` - stable identifier used for lookup
  * `:name` - display name
  * `:category` - what kind of item it is
  * `:ability` - the ability a check with this tool uses, for tools
  * `:contents` - what a pack holds
  * `:variants` - the forms a spellcasting focus can take
  """
  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          category: category(),
          ability: :str | :dex | :con | :int | :wis | :cha | nil,
          contents: [entry()],
          variants: [String.t()]
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      slug: data.slug,
      name: data.name,
      category: validate_category!(data.category),
      ability: validate_ability!(data[:ability]),
      contents: Enum.map(data[:contents] || [], &entry/1),
      variants: data[:variants] || []
    }
  end

  defp entry({slug, quantity}) when is_binary(slug) and is_integer(quantity) and quantity > 0,
    do: %{item: slug, quantity: quantity}

  defp entry(slug) when is_binary(slug), do: %{item: slug, quantity: 1}

  defp validate_category!(category) when category in @categories, do: category

  defp validate_category!(category),
    do: raise(ArgumentError, "unknown item category: #{inspect(category)}")

  defp validate_ability!(nil), do: nil
  defp validate_ability!(ability) when ability in @abilities, do: ability

  defp validate_ability!(ability),
    do: raise(ArgumentError, "unknown ability: #{inspect(ability)}")
end
