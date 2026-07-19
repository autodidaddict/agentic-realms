defmodule Srd.Content.Armor do
  @moduledoc """
  An SRD armor.
  """
  @categories ~w(light medium heavy shield)a

  @enforce_keys [:slug, :name, :category, :base_ac]
  defstruct [:slug, :name, :category, :base_ac, :strength, stealth_disadvantage: false]

  @type category :: :light | :medium | :heavy | :shield

  @typedoc """
  An SRD armor:

  * `:slug` - stable identifier used for lookup
  * `:name` - display name
  * `:category` - light, medium, heavy, or shield
  * `:base_ac` - the base Armor Class (for a shield, the bonus it grants)
  * `:strength` - the minimum Strength score the armor requires, or `nil`
  * `:stealth_disadvantage` - whether wearing it gives disadvantage on Stealth
  """
  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          category: category(),
          base_ac: non_neg_integer(),
          strength: non_neg_integer() | nil,
          stealth_disadvantage: boolean()
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      slug: data.slug,
      name: data.name,
      category: validate_category!(data.category),
      base_ac: data.base_ac,
      strength: data[:strength],
      stealth_disadvantage: data[:stealth_disadvantage] || false
    }
  end

  defp validate_category!(category) when category in @categories, do: category

  defp validate_category!(category),
    do: raise(ArgumentError, "unknown armor category: #{inspect(category)}")
end
