defmodule Srd.Rules.Skill do
  @moduledoc """
  Skills and skill checks.
  """

  @skills %{
    acrobatics: :dex,
    animal_handling: :wis,
    arcana: :int,
    athletics: :str,
    deception: :cha,
    history: :int,
    insight: :wis,
    intimidation: :cha,
    investigation: :int,
    medicine: :wis,
    nature: :int,
    perception: :wis,
    performance: :cha,
    persuasion: :cha,
    religion: :int,
    sleight_of_hand: :dex,
    stealth: :dex,
    survival: :wis
  }

  @type skill ::
          :acrobatics
          | :animal_handling
          | :arcana
          | :athletics
          | :deception
          | :history
          | :insight
          | :intimidation
          | :investigation
          | :medicine
          | :nature
          | :perception
          | :performance
          | :persuasion
          | :religion
          | :sleight_of_hand
          | :stealth
          | :survival

  @type ability :: :str | :dex | :con | :int | :wis | :cha

  @doc "Every skill."
  @spec all() :: [skill()]
  def all, do: Map.keys(@skills)

  @doc "The ability that governs a skill."
  @spec ability(skill()) :: ability()
  def ability(skill), do: Map.fetch!(@skills, skill)

  @doc "The skills governed by an ability."
  @spec by_ability(ability()) :: [skill()]
  def by_ability(ability) do
    for {skill, ^ability} <- @skills, do: skill
  end

  @doc """
  The modifier for a skill check: the ability modifier, plus the proficiency
  bonus if proficient, doubled with expertise.
  """
  @spec check_modifier(integer(), integer(), keyword()) :: integer()
  def check_modifier(ability_modifier, proficiency, opts \\ []) do
    proficient? = Keyword.get(opts, :proficient?, false)
    expertise? = Keyword.get(opts, :expertise?, false)
    ability_modifier + proficiency_applied(proficiency, proficient?, expertise?)
  end

  defp proficiency_applied(_proficiency, false, _), do: 0
  defp proficiency_applied(proficiency, true, false), do: proficiency
  defp proficiency_applied(proficiency, true, true), do: proficiency * 2
end
