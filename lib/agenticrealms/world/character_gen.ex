defmodule AgenticRealms.World.CharacterGen do
  @moduledoc """
  Feature 020 — deterministic character generation from the configured defaults.

  Character creation is not interactive yet, so every new character is built
  here. The SRD says what a character *may* be; this decides what it *is*, and
  that division is the whole reason this module lives in the game rather than in
  `srd_5e`. The rules package supplies the raw material — the standard array,
  the background's legal spreads, each class's skill list — and every choice
  among it is made below.

  Pure: a keyword list in, a command payload out. No repository access and no
  randomness, so two players created with the same configuration are identical
  (FR-012) and a replayed `CharacterCreated` never disagrees with what was
  originally recorded.

  Proficiency lists come out as sorted strings, matching what the event carries
  on the wire and what the read model stores.
  """

  alias Srd.Content.Background
  alias Srd.Content.Backgrounds
  alias Srd.Content.Classes
  alias Srd.Content.Species
  alias Srd.Rules.Ability
  alias Srd.Rules.Hitpoints
  alias Srd.Rules.Skill

  @doc """
  The default character, from `:agenticrealms, :character_defaults`.
  """
  @spec default() :: map()
  def default do
    default(Application.fetch_env!(:agenticrealms, :character_defaults))
  end

  @doc """
  The default character for an explicit configuration.

  Expects `:species`, `:class`, `:background`, `:size`, `:species_skill`, and
  `:species_feat`.
  """
  @spec default(keyword() | map()) :: map()
  def default(config) do
    config = Map.new(config)

    species = fetch!(Species.get(config.species), "species", config.species)
    class = fetch!(Classes.get(config.class), "class", config.class)
    background = fetch!(Backgrounds.get(config.background), "background", config.background)

    priority = ability_priority(class)
    abilities = assign_scores(priority) |> apply_background_increases(background, priority)
    modifiers = Map.new(abilities, fn {key, score} -> {key, Ability.modifier(score)} end)

    skills = skills(class, background, config.species_skill, modifiers)

    %{
      species_slug: species.slug,
      class_slug: class.slug,
      background_slug: background.slug,
      size: to_string(config.size),
      abilities: abilities,
      skill_proficiencies: sorted_strings(skills),
      save_proficiencies: sorted_strings(class.saving_throws),
      feat_slugs: sorted_strings([background.origin_feat, config.species_feat]),
      max_hp: Hitpoints.starting(class.hit_die, modifiers.con)
    }
  end

  # --- ability scores ------------------------------------------------------

  @doc """
  The order in which a class's abilities matter, used wherever generation needs
  a deterministic tiebreak: the primary ability first, then the saving throws it
  is proficient in, then the remaining abilities in canonical order.

  Where the SRD offers a choice of primary ability — a Fighter runs on Strength
  *or* Dexterity — the first named wins. Where it requires both, as a Monk needs
  Dexterity *and* Wisdom, both come first.

  For a Fighter this is `[:str, :con, :dex, :int, :wis, :cha]`.
  """
  @spec ability_priority(Srd.Content.Class.t()) :: [Ability.t()]
  def ability_priority(class) do
    primary =
      case class.primary_ability do
        {:any, [first | _]} -> [first]
        {:all, abilities} -> abilities
      end

    Enum.uniq(primary ++ class.saving_throws ++ Ability.all())
  end

  # Deal the standard array down the priority order: highest score to the
  # ability the class cares about most.
  defp assign_scores(priority) do
    priority
    |> Enum.zip(Ability.standard_array())
    |> Map.new()
  end

  # The 2024 rules attach ability score increases to the background rather than
  # the species. Of the spreads the SRD allows, take [2, 1] and put the larger
  # increase on the highest-priority ability the background offers.
  defp apply_background_increases(abilities, background, priority) do
    [larger, smaller] = Enum.find(Background.spreads(), &(length(&1) == 2))

    background.ability_scores
    |> Enum.sort_by(&Enum.find_index(priority, fn ability -> ability == &1 end))
    |> Enum.zip([larger, smaller])
    |> Enum.reduce(abilities, fn {ability, bump}, acc ->
      Map.update!(acc, ability, &(&1 + bump))
    end)
  end

  # --- skills --------------------------------------------------------------

  # Order matters: the fixed grants land first, so the class's free picks are
  # never spent on something the character already has.
  defp skills(class, background, species_skill, modifiers) do
    granted = background.skills ++ [species_skill]

    picks =
      class.skill_choice.from
      |> Enum.reject(&(&1 in granted))
      |> rank(modifiers)
      |> Enum.take(class.skill_choice.choose)

    Enum.uniq(granted ++ picks)
  end

  # Best modifier first, ties broken by name so the result never depends on the
  # order the content happens to list.
  defp rank(skills, modifiers) do
    Enum.sort_by(skills, &{-Map.fetch!(modifiers, Skill.ability(&1)), Skill.name(&1)})
  end

  # --- helpers -------------------------------------------------------------

  defp sorted_strings(values) do
    values |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()
  end

  defp fetch!(nil, kind, slug),
    do: raise(ArgumentError, "character_defaults names an unknown #{kind}: #{inspect(slug)}")

  defp fetch!(content, _kind, _slug), do: content
end
