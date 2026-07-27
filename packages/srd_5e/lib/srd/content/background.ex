defmodule Srd.Content.Background do
  @moduledoc """
  An SRD background.

  A background carries everything the 2024 rules make it responsible for at
  character creation: the ability scores it can raise, the origin feat it
  grants, two skill proficiencies, a tool proficiency, and a choice of starting
  equipment.
  """
  alias Srd.Content.Bundle
  alias Srd.Content.Choice
  alias Srd.Rules.Skill

  @abilities ~w(str dex con int wis cha)a
  @spreads [[2, 1], [1, 1, 1]]

  @enforce_keys [:slug, :name, :ability_scores, :origin_feat, :skills, :tool, :equipment]
  defstruct [
    :slug,
    :name,
    :ability_scores,
    :origin_feat,
    :origin_feat_option,
    :skills,
    :tool,
    :equipment
  ]

  @typedoc """
  An SRD background:

  * `:slug` - stable identifier used for lookup
  * `:name` - display name
  * `:ability_scores` - the three abilities it can raise
  * `:origin_feat` - the slug of the origin feat it grants
  * `:origin_feat_option` - the option the background fixes for that feat, such
    as the spell list for Magic Initiate, or `nil`
  * `:skills` - the two skills it grants proficiency in
  * `:tool` - the tool proficiency, as a choice of one
  * `:equipment` - a choice between a bundle of gear and 50 GP
  """
  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          ability_scores: [atom()],
          origin_feat: String.t(),
          origin_feat_option: String.t() | nil,
          skills: [Skill.skill()],
          tool: Choice.t(),
          equipment: Choice.t()
        }

  @doc false
  @spec new(map()) :: t()
  def new(data) do
    %__MODULE__{
      slug: data.slug,
      name: data.name,
      ability_scores: Enum.map(data.ability_scores, &validate_ability!/1),
      origin_feat: data.origin_feat,
      origin_feat_option: data[:origin_feat_option],
      skills: Enum.map(data.skills, &validate_skill!/1),
      tool: Choice.new(data.tool),
      equipment: Bundle.choice(data.equipment)
    }
  end

  @doc """
  How a background's ability score increases can be spread: one score by 2 and
  another by 1, or all three by 1.

      iex> Srd.Content.Background.spreads()
      [[2, 1], [1, 1, 1]]
  """
  @spec spreads() :: [[pos_integer()]]
  def spreads, do: @spreads

  defp validate_ability!(ability) when ability in @abilities, do: ability

  defp validate_ability!(ability),
    do: raise(ArgumentError, "unknown ability: #{inspect(ability)}")

  defp validate_skill!(skill) do
    if skill in Skill.all() do
      skill
    else
      raise ArgumentError, "unknown skill: #{inspect(skill)}"
    end
  end
end
