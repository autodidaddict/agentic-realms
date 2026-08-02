defmodule AgenticRealms.World.CharacterGen do
  @moduledoc """
  Deterministic character generation: the choices nobody made.

  The SRD says what a character *may* be; this decides what it *is*, and that
  division is the whole reason this module lives in the game rather than in
  `srd_5e`. The rules package supplies the raw material — the standard array,
  the background's legal spreads, each class's skill list — and every choice
  among it is made below.

  Two callers, and they want different things.

  `complete/1` takes a player's in-progress draft and fills whatever they were
  not asked, so the facade can hand the validator a whole character. It exists
  because the creation dialog grows one step per user story: until every story
  ships, a draft arrives with no ability scores or no skill picks, and that is
  not something to reject — it is something to finish. It fills **only what is
  missing**, so a choice the player did make is never overwritten, and once the
  dialog asks everything it quietly stops having anything to do.

  `default/0` builds a whole character from configuration, with no player
  involved. It is what seeds and tests use.

  Pure either way: no repository access and no randomness, so two identical
  inputs produce two identical characters and a replayed `CharacterCreated`
  never disagrees with what was originally recorded.

  Proficiency lists come out as sorted strings, matching what the event carries
  on the wire and what the read model stores.
  """

  alias AgenticRealms.World.CharacterDraft, as: Draft
  alias Srd.Character
  alias Srd.Content.Background
  alias Srd.Content.Backgrounds
  alias Srd.Content.Classes
  alias Srd.Content.Species
  alias Srd.Rules.Ability
  alias Srd.Rules.Hitpoints
  alias Srd.Rules.Skill

  @doc """
  A draft with every open decision settled.

  Fills only what is missing. Species, class, and background are never filled:
  those are the player's first and only required choices, and a draft without
  them is a validation error rather than something to guess at.

  Deterministic, so the same draft always completes to the same character.
  """
  @spec complete(Draft.t()) :: Draft.t()
  def complete(%Draft{} = draft) do
    if draft.species_slug && draft.class_slug && draft.background_slug do
      draft
      |> fill_array()
      |> fill_spread()
      |> fill_skill_picks()
      |> fill_choices()
    else
      draft
    end
  end

  # The standard array dealt down the class's priority order, highest score to
  # the ability the class cares about most.
  defp fill_array(%Draft{array: array} = draft) when map_size(array) > 0, do: draft

  defp fill_array(%Draft{} = draft) do
    class = Classes.get(draft.class_slug)

    class
    |> ability_priority()
    |> Enum.zip(Ability.standard_array())
    |> Enum.reduce(draft, fn {ability, value}, acc ->
      Draft.assign_ability(acc, ability, value)
    end)
  end

  # Of the spreads the SRD allows, take [2, 1] and put the larger increase on
  # the highest-priority ability the background offers.
  defp fill_spread(%Draft{spread: spread} = draft) when not is_nil(spread), do: draft

  defp fill_spread(%Draft{} = draft) do
    background = Backgrounds.get(draft.background_slug)
    priority = draft.class_slug |> Classes.get() |> ability_priority()

    [larger, smaller] =
      background.ability_scores
      |> Enum.sort_by(&Enum.find_index(priority, fn ability -> ability == &1 end))
      |> Enum.take(2)

    Draft.put_spread(draft, {:split, larger, smaller})
  end

  # The best-modifier picks the class offers, skipping anything already granted
  # so a pick is never spent on a proficiency the character already has.
  defp fill_skill_picks(%Draft{skill_picks: [_ | _]} = draft), do: draft

  defp fill_skill_picks(%Draft{} = draft) do
    case Enum.find(Draft.open_choices(draft), &(&1.key == :class_skills)) do
      nil ->
        draft

      %{choice: choice} ->
        granted = Draft.grants(draft).skills
        modifiers = modifiers_of(draft)

        choice.from
        |> Enum.reject(&(&1 in granted))
        |> rank(modifiers)
        |> Enum.take(choice.choose)
        |> Enum.reduce(draft, &Draft.toggle_skill(&2, &1))
    end
  end

  # Everything else the content asks for. Takes options in the order the content
  # lists them, which is arbitrary but stable — and stability is the property
  # that matters, because a replay must reproduce the same character.
  defp fill_choices(%Draft{} = draft) do
    draft
    |> Draft.open_choices()
    |> Enum.reject(&(&1.key == :class_skills))
    |> Enum.reduce(draft, fn open, acc ->
      held = acc.choices |> Map.get(open.key, []) |> Enum.map(&option_id/1)
      wanted = open.choice.choose - length(held)

      if wanted > 0 do
        open.choice.from
        |> Enum.map(&option_id/1)
        |> Enum.reject(&(&1 in held))
        |> prefer(open.key)
        |> Enum.take(wanted)
        |> Enum.reduce(acc, fn option, inner ->
          Draft.toggle_choice(inner, open.key, option)
        end)
      else
        acc
      end
    end)
  end

  # Content order is arbitrary, and for one choice that shows. A human's sizes
  # are listed small before medium, so taking the first would quietly make every
  # unasked human small. Size is the one place the configured default has an
  # opinion worth honouring; everywhere else the content's own order stands.
  defp prefer(options, :species_size) do
    default = configured_size()
    if default in options, do: [default | List.delete(options, default)], else: options
  end

  defp prefer(options, _key), do: options

  defp configured_size do
    :agenticrealms
    |> Application.get_env(:character_defaults, [])
    |> Keyword.get(:size, :medium)
  end

  defp option_id(%{slug: slug}), do: slug
  defp option_id(option), do: option

  defp modifiers_of(%Draft{} = draft) do
    scores = Draft.scores(draft)
    Map.new(Ability.all(), &{&1, Ability.modifier(Map.get(scores, &1, 10))})
  end

  @doc """
  The command payload for a completed draft.

  What `CreateCharacter` carries, assembled from the draft so the aggregate
  still generates nothing, looks nothing up, and defaults nothing.
  """
  @spec payload(Draft.t()) :: map()
  def payload(%Draft{} = draft) do
    class = Classes.get(draft.class_slug)
    scores = Draft.scores(draft)
    con = Ability.modifier(Map.fetch!(scores, :con))

    %{
      character_name: String.trim(draft.name),
      species_slug: draft.species_slug,
      class_slug: draft.class_slug,
      background_slug: draft.background_slug,
      size: draft |> Draft.size() |> to_string(),
      lineage_slug: Draft.lineage_slug(draft),
      abilities: scores,
      skill_proficiencies: sorted_strings(Draft.skill_proficiencies(draft)),
      save_proficiencies: sorted_strings(Character.grants(Draft.selections(draft)).saves),
      feat_slugs: Draft.feat_slugs(draft),
      choices: Draft.stored_choices(draft),
      max_hp: Hitpoints.starting(class.hit_die, con)
    }
  end

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
      character_name: Map.get(config, :name, "Adventurer"),
      species_slug: species.slug,
      lineage_slug: nil,
      choices: %{},
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
