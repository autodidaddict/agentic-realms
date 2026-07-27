defmodule Srd.Content.Class do
  @moduledoc """
  An SRD class.

  This carries what a character builder needs: the core traits, every choice the
  class asks for, and the features it grants at each level. Subclasses are their
  own content, reached with `Srd.Content.Subclasses.for_class/1`.
  """
  alias Srd.Content.Bundle
  alias Srd.Content.Choice
  alias Srd.Content.Feature
  alias Srd.Dice.Expr
  alias Srd.Rules.Skill

  @abilities ~w(str dex con int wis cha)a
  @armor ~w(light medium heavy shield)a

  @enforce_keys [
    :slug,
    :name,
    :primary_ability,
    :hit_die,
    :saving_throws,
    :skill_choice,
    :starting_equipment,
    :subclass_level
  ]
  defstruct [
    :slug,
    :name,
    :primary_ability,
    :hit_die,
    :saving_throws,
    :skill_choice,
    :tool_proficiency,
    :starting_equipment,
    :subclass_level,
    :spellcasting,
    weapon_proficiencies: [],
    armor_training: [],
    features: []
  ]

  @typedoc """
  The class's primary ability, and how it is met. Most classes name one ability;
  a fighter's is Strength *or* Dexterity, and a monk's is Dexterity *and*
  Wisdom. Multiclassing requires a 13 in it, so which of the two applies
  matters.
  """
  @type primary_ability :: {:all | :any, [atom()]}

  @typedoc """
  A weapon proficiency: a whole category, or a category narrowed to the weapons
  carrying one of the given properties, as a rogue's martial weapons are
  narrowed to Finesse and Light.
  """
  @type weapon_proficiency :: :simple | :martial | {:simple | :martial, [atom()]}

  @typedoc "How the class casts, when it casts at all."
  @type spellcasting :: %{ability: atom(), kind: :prepared | :pact}

  @typedoc """
  An SRD class:

  * `:slug` - stable identifier used for lookup
  * `:name` - display name
  * `:primary_ability` - the ability the class runs on
  * `:hit_die` - the hit point die gained per level
  * `:saving_throws` - the two saving throws it is proficient in
  * `:skill_choice` - the skill proficiencies it offers
  * `:tool_proficiency` - the tool proficiency it offers, or `nil`
  * `:starting_equipment` - a choice between equipment bundles
  * `:subclass_level` - the level at which a subclass is chosen
  * `:spellcasting` - how the class casts, or `nil`
  * `:weapon_proficiencies` - the weapons it can use
  * `:armor_training` - the armor it is trained in
  * `:features` - what it grants, by level
  """
  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          primary_ability: primary_ability(),
          hit_die: Expr.t(),
          saving_throws: [atom()],
          skill_choice: Choice.t(),
          tool_proficiency: Choice.t() | nil,
          starting_equipment: Choice.t(),
          subclass_level: pos_integer(),
          spellcasting: spellcasting() | nil,
          weapon_proficiencies: [weapon_proficiency()],
          armor_training: [atom()],
          features: [Feature.t()]
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      slug: data.slug,
      name: data.name,
      primary_ability: validate_primary!(data.primary_ability),
      hit_die: Expr.parse!(data.hit_die),
      saving_throws: Enum.map(data.saving_throws, &validate_ability!/1),
      skill_choice: skill_choice(data.skill_choice),
      tool_proficiency: tool_proficiency(data[:tool_proficiency]),
      starting_equipment: Bundle.choice(data.starting_equipment),
      subclass_level: data.subclass_level,
      spellcasting: validate_spellcasting!(data[:spellcasting]),
      weapon_proficiencies: data[:weapon_proficiencies] || [],
      armor_training: Enum.map(data[:armor_training] || [], &validate_armor!/1),
      features: Enum.map(data[:features] || [], &Feature.new/1)
    }
  end

  @doc """
  Whether a set of ability scores meets the class's primary ability
  requirement, which is what multiclassing into it takes.

      iex> Srd.Content.Classes.get("monk")
      ...> |> Srd.Content.Class.primary_ability_met?(%{dex: 15, wis: 13})
      true

      iex> Srd.Content.Classes.get("monk")
      ...> |> Srd.Content.Class.primary_ability_met?(%{dex: 15})
      false
  """
  @spec primary_ability_met?(t(), map(), pos_integer()) :: boolean()
  def primary_ability_met?(%__MODULE__{primary_ability: {rule, abilities}}, scores, minimum \\ 13) do
    check = fn ability -> Map.get(scores, ability, 0) >= minimum end

    case rule do
      :all -> Enum.all?(abilities, check)
      :any -> Enum.any?(abilities, check)
    end
  end

  defp skill_choice(data), do: Choice.new(%{data | from: Enum.map(data.from, &validate_skill!/1)})

  defp tool_proficiency(nil), do: nil
  defp tool_proficiency(data), do: Choice.new(data)

  defp validate_primary!({rule, abilities}) when rule in [:all, :any] and is_list(abilities) do
    {rule, Enum.map(abilities, &validate_ability!/1)}
  end

  defp validate_primary!(primary),
    do: raise(ArgumentError, "unknown primary ability: #{inspect(primary)}")

  defp validate_ability!(ability) when ability in @abilities, do: ability

  defp validate_ability!(ability),
    do: raise(ArgumentError, "unknown ability: #{inspect(ability)}")

  defp validate_armor!(armor) when armor in @armor, do: armor

  defp validate_armor!(armor),
    do: raise(ArgumentError, "unknown armor training: #{inspect(armor)}")

  defp validate_skill!(skill) do
    if skill in Skill.all() do
      skill
    else
      raise ArgumentError, "unknown skill: #{inspect(skill)}"
    end
  end

  defp validate_spellcasting!(nil), do: nil

  defp validate_spellcasting!(%{ability: ability, kind: kind} = spellcasting)
       when kind in [:prepared, :pact] do
    validate_ability!(ability)
    spellcasting
  end

  defp validate_spellcasting!(spellcasting),
    do: raise(ArgumentError, "unknown spellcasting: #{inspect(spellcasting)}")
end
