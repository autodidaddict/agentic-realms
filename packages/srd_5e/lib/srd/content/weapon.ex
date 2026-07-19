defmodule Srd.Content.Weapon do
  @moduledoc """
  An SRD weapon.
  """
  alias Srd.Dice.Expr
  alias Srd.Rules.Damage

  @masteries ~w(cleave graze nick push sap slow topple vex)a

  @enforce_keys [:slug, :name, :category, :kind, :damage, :damage_type, :mastery]
  defstruct [
    :slug,
    :name,
    :category,
    :kind,
    :damage,
    :damage_type,
    :mastery,
    :versatile,
    properties: []
  ]

  @type category :: :simple | :martial
  @type kind :: :melee | :ranged

  @type property ::
          :ammunition
          | :finesse
          | :heavy
          | :light
          | :loading
          | :reach
          | :special
          | :thrown
          | :two_handed
          | :versatile

  @typedoc "A 2024 SRD weapon mastery property."
  @type mastery :: :cleave | :graze | :nick | :push | :sap | :slow | :topple | :vex

  @typedoc """
  An SRD weapon:

  * `:slug` - stable identifier used for lookup
  * `:name` - display name
  * `:category` - simple or martial
  * `:kind` - melee or ranged
  * `:damage` - the damage dice
  * `:damage_type` - the damage type dealt
  * `:mastery` - the weapon's mastery property
  * `:versatile` - the two-handed damage dice, present when the weapon is versatile
  * `:properties` - the weapon's properties
  """
  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          category: category(),
          kind: kind(),
          damage: Expr.t(),
          damage_type: Damage.damage_type(),
          mastery: mastery(),
          versatile: Expr.t() | nil,
          properties: [property()]
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      slug: data.slug,
      name: data.name,
      category: data.category,
      kind: data.kind,
      damage: Expr.parse!(data.damage),
      damage_type: validate_type!(data.damage_type),
      mastery: validate_mastery!(data.mastery),
      versatile: parse_optional(data[:versatile]),
      properties: data[:properties] || []
    }
  end

  defp validate_type!(type) do
    if type in Damage.types() do
      type
    else
      raise ArgumentError, "unknown damage type: #{inspect(type)}"
    end
  end

  defp validate_mastery!(mastery) when mastery in @masteries, do: mastery

  defp validate_mastery!(mastery),
    do: raise(ArgumentError, "unknown weapon mastery: #{inspect(mastery)}")

  defp parse_optional(nil), do: nil
  defp parse_optional(die), do: Expr.parse!(die)
end
