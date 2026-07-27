defmodule Srd.Content.Lineage do
  @moduledoc """
  One option within a species trait that offers a further choice: an Elven
  Lineage, a Gnomish Lineage, a Fiendish Legacy, a Draconic Ancestry, or a Giant
  Ancestry.

  The 2024 rules have no subraces. Each of these is a trait of one species, so a
  lineage is only ever reached through the species that offers it - see
  `Srd.Content.Species`.
  """
  alias Srd.Content.Feature
  alias Srd.Rules.Damage

  @enforce_keys [:slug, :name]
  defstruct [:slug, :name, :damage_type, features: []]

  @typedoc """
  A lineage option:

  * `:slug` - stable identifier, unique within its species
  * `:name` - display name
  * `:damage_type` - the damage type the option determines, for draconic
    ancestry, or `nil`
  * `:features` - what the option grants, by level
  """
  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          damage_type: Damage.damage_type() | nil,
          features: [Feature.t()]
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      slug: data.slug,
      name: data.name,
      damage_type: validate_damage_type!(data[:damage_type]),
      features: Enum.map(data[:features] || [], &Feature.new/1)
    }
  end

  defp validate_damage_type!(nil), do: nil

  defp validate_damage_type!(type) do
    if type in Damage.types() do
      type
    else
      raise ArgumentError, "unknown damage type: #{inspect(type)}"
    end
  end
end
