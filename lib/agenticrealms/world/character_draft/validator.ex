defmodule AgenticRealms.World.CharacterDraft.Validator do
  @moduledoc """
  Feature 021 — is this a legal SRD character?

  The dialog is a client, so its constraints are a convenience rather than an
  authority. This runs before dispatch and refuses anything the SRD does not
  allow, whatever the dialog let the player click.

  **It knows no SRD rules.** For every decision `Srd.Character.choices/1`
  offered, it checks that the draft holds the right number of picks and that
  each one was among the options. It never learns what a fighting style is; it
  learns that the submitted slug has to be in the list the package handed over.
  That is what makes a choice the content gains tomorrow validate correctly with
  no change here.

  Ability scores are checked the same way, against
  `Srd.Rules.Ability.standard_array/0`, `Srd.Content.Background.spreads/0`, and
  the background's own `ability_scores` — lists the package supplies rather than
  rules this module carries.

  ## It expects a completed draft

  Every rule is unconditional. There is no "skip this if empty" clause, because
  a draft reaching the write side with no ability scores is not a legal
  character no matter which user story has shipped. Completing a draft is
  `AgenticRealms.World.CharacterGen.complete/1`'s job, and the facade does it
  first.

  ## Not here: uniqueness

  Whether a name is already taken is a property of the world rather than of the
  draft, and the `AgenticRealms.World.CharacterName` aggregate is what decides
  it. This checks the name's shape and nothing more.
  """

  alias AgenticRealms.World.CharacterDraft, as: Draft
  alias Srd.Content.Background
  alias Srd.Content.Backgrounds
  alias Srd.Content.Classes
  alias Srd.Content.Species
  alias Srd.Rules.Ability

  @max_name_length 32
  @max_score 20

  @typedoc "A field the player can fix, and what is wrong with it."
  @type error :: {atom(), String.t()}

  @doc """
  `:ok`, or every problem at once so the dialog can show them together.
  """
  @spec validate(Draft.t()) :: :ok | {:error, [error()]}
  def validate(%Draft{} = draft) do
    errors =
      Enum.concat([
        name_errors(draft),
        selection_errors(draft),
        ability_errors(draft),
        skill_errors(draft),
        choice_errors(draft)
      ])

    if errors == [], do: :ok, else: {:error, errors}
  end

  @doc """
  Whether a draft would be accepted. For gating the confirm control.
  """
  @spec valid?(Draft.t()) :: boolean()
  def valid?(%Draft{} = draft), do: validate(draft) == :ok

  # --- name ----------------------------------------------------------------

  defp name_errors(%Draft{name: name}) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> [{:name, "Your character needs a name."}]
      String.length(trimmed) > @max_name_length -> [{:name, too_long()}]
      true -> []
    end
  end

  defp too_long, do: "A name can be at most #{@max_name_length} characters."

  # --- species, class, background -------------------------------------------

  defp selection_errors(%Draft{} = draft) do
    [
      resolves(draft.species_slug, &Species.get/1, :species_slug, "species"),
      resolves(draft.class_slug, &Classes.get/1, :class_slug, "class"),
      resolves(draft.background_slug, &Backgrounds.get/1, :background_slug, "background")
    ]
    |> Enum.concat()
  end

  defp resolves(nil, _get, field, what), do: [{field, "Choose a #{what}."}]

  defp resolves(slug, get, field, what) do
    if get.(slug), do: [], else: [{field, "There is no such #{what}."}]
  end

  # --- ability scores -------------------------------------------------------

  defp ability_errors(%Draft{} = draft) do
    array_errors(draft) ++ spread_errors(draft) ++ cap_errors(draft)
  end

  # The standard array, each value used exactly once across the six abilities.
  defp array_errors(%Draft{array: array}) do
    assigned = array |> Map.values() |> Enum.sort()
    expected = Ability.standard_array() |> Enum.sort()

    cond do
      Map.keys(array) |> Enum.sort() != Enum.sort(Ability.all()) ->
        [{:array, "Every ability needs a score."}]

      assigned != expected ->
        [{:array, "Use each of the standard array's scores exactly once."}]

      true ->
        []
    end
  end

  defp spread_errors(%Draft{spread: nil}), do: [{:spread, "Choose how to spread your increases."}]

  defp spread_errors(%Draft{} = draft) do
    offered = raisable(draft.background_slug)
    increases = Draft.increases(draft)
    shape = increases |> Map.values() |> Enum.sort(:desc)

    cond do
      not Enum.member?(Background.spreads(), shape) ->
        [{:spread, "That is not a spread the rules allow."}]

      Enum.any?(Map.keys(increases), &(&1 not in offered)) ->
        [{:spread, "Your background does not raise that ability."}]

      map_size(increases) != length(shape) ->
        [{:spread, "Each increase goes to a different ability."}]

      true ->
        []
    end
  end

  defp raisable(nil), do: []

  defp raisable(slug) do
    case Backgrounds.get(slug) do
      nil -> []
      background -> background.ability_scores
    end
  end

  defp cap_errors(%Draft{} = draft) do
    if Enum.any?(Draft.scores(draft), fn {_ability, score} -> score > @max_score end) do
      [{:array, "No ability score may exceed #{@max_score}."}]
    else
      []
    end
  end

  # --- skills ---------------------------------------------------------------

  defp skill_errors(%Draft{} = draft) do
    case Enum.find(Draft.open_choices(draft), &(&1.key == :class_skills)) do
      nil ->
        if draft.skill_picks == [], do: [], else: [{:skill_picks, "Your class offers no skills."}]

      %{choice: choice} ->
        picks = draft.skill_picks
        granted = Draft.grants(draft).skills

        cond do
          length(picks) != choice.choose ->
            [{:skill_picks, "Choose #{choice.choose} skills."}]

          picks != Enum.uniq(picks) ->
            [{:skill_picks, "Choose each skill only once."}]

          Enum.any?(picks, &(&1 not in choice.from)) ->
            [{:skill_picks, "Your class does not offer that skill."}]

          Enum.any?(picks, &(&1 in granted)) ->
            [{:skill_picks, "You already have that skill; spend the pick elsewhere."}]

          true ->
            []
        end
    end
  end

  # --- everything else ------------------------------------------------------

  # The generic rule, and the reason this module needs no rules of its own: for
  # each choice the package offered, exactly `choose` picks, each of them from
  # `from`. A key the package did not offer is an error, which is what stops a
  # forged submission from carrying a decision nobody asked for.
  defp choice_errors(%Draft{} = draft) do
    open = Draft.open_choices(draft) |> Enum.reject(&(&1.key == :class_skills))
    offered = MapSet.new(open, & &1.key)

    unexpected =
      draft.choices
      |> Map.keys()
      |> Enum.reject(&(&1 == :class_skills))
      |> Enum.reject(&MapSet.member?(offered, &1))
      |> Enum.map(&{:choices, "Nothing asked for #{inspect(&1)}."})

    unexpected ++ Enum.flat_map(open, &one_choice_errors(draft, &1))
  end

  defp one_choice_errors(%Draft{} = draft, open) do
    picks = Map.get(draft.choices, open.key, [])
    options = option_set(open.choice)

    cond do
      length(picks) != open.choice.choose ->
        [{open.key, "Choose #{open.choice.choose} for #{open.label}."}]

      picks != Enum.uniq(picks) ->
        [{open.key, "Choose each option only once for #{open.label}."}]

      Enum.any?(picks, &(not MapSet.member?(options, option_id(&1)))) ->
        [{open.key, "That is not an option for #{open.label}."}]

      true ->
        []
    end
  end

  # Options arrive as slugs, atoms, or structs depending on the choice's kind.
  # Comparing identity rather than shape keeps this from having to know which.
  defp option_set(%{from: from}), do: MapSet.new(from, &option_id/1)

  defp option_id(%{slug: slug}), do: slug
  defp option_id(option), do: option
end
