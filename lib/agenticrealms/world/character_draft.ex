defmodule AgenticRealms.World.CharacterDraft do
  @moduledoc """
  A character being made, before it exists.

  Held in the creating player's LiveView socket and nowhere else. Never
  persisted, never broadcast, never in a registry: a draft belongs to one
  player's one session and is meaningless to any other process on any other
  node, which is the node-local state Principle I permits. Abandoning creation
  therefore leaves nothing behind, and no half-made character can ever be
  mistaken for a real one.

  The struct names the player's decisions and nothing about what those decisions
  *are*. `choices` is keyed by whatever `Srd.Character.choices/1` returns, so a
  fighter's draft holds a Fighting Style without this module, the LiveView, or
  the validator ever learning that fighting styles exist. That is what lets a
  species or class gain a new kind of choice with no change here.

  A draft may be incomplete. Until every user story ships, the dialog asks only
  what has shipped, and `AgenticRealms.World.CharacterGen.complete/1` fills the
  rest before the facade validates it.
  """

  alias AgenticRealms.World.CharacterDraft
  alias Srd.Character
  alias Srd.Content.Background
  alias Srd.Content.Backgrounds
  alias Srd.Content.Classes
  alias Srd.Rules.Ability
  alias Srd.Rules.PointBuy
  alias Srd.Rules.Proficiency
  alias Srd.Rules.Skill

  @steps [:identity, :abilities, :skills, :specializations, :review]

  @typedoc "Which step the dialog is showing."
  @type step :: :identity | :abilities | :skills | :specializations | :review

  @typedoc """
  How a background's ability score increases are spread. `{:split, ability,
  ability}` is the +2/+1 form; `{:even, abilities}` is +1 to all three.
  """
  @type spread :: {:split, Ability.t(), Ability.t()} | {:even, [Ability.t()]} | nil

  @typedoc "What the availability check last said about the name."
  @type name_status :: :unchecked | :checking | :available | :taken | :invalid

  defstruct step: :identity,
            name: "",
            name_status: :unchecked,
            species_slug: nil,
            class_slug: nil,
            background_slug: nil,
            bought: %{},
            spread: nil,
            skill_picks: [],
            choices: %{},
            errors: []

  @type t :: %__MODULE__{
          step: step(),
          name: String.t(),
          name_status: name_status(),
          species_slug: String.t() | nil,
          class_slug: String.t() | nil,
          background_slug: String.t() | nil,
          bought: %{Ability.t() => pos_integer()},
          spread: spread(),
          skill_picks: [atom()],
          choices: %{Character.choice_key() => [term()]},
          errors: [{atom(), String.t()}]
        }

  @doc "An empty draft, at the first step."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The steps a dialog walks, in order."
  @spec steps() :: [step()]
  def steps, do: @steps

  @doc """
  Set the character's name. Clears nothing: the name has no dependents.
  """
  @spec put_name(t(), String.t()) :: t()
  def put_name(%__MODULE__{} = draft, name) when is_binary(name) do
    %{draft | name: name, name_status: :unchecked, errors: []}
  end

  @doc """
  Set the species, class, or background, discarding exactly what the new
  selection invalidates.

  Nothing here knows what depends on what. The draft's picks are re-checked
  against `Srd.Character.choices/1` for the new selections, and any entry the
  new selections no longer offer is dropped. A background change additionally
  clears the ability spread, because a background names which three abilities
  its increases may go to and the old answer is about the wrong three.
  """
  @spec put_selection(t(), :species | :class | :background, String.t() | nil) :: t()
  def put_selection(%__MODULE__{} = draft, field, slug)
      when field in [:species_slug, :class_slug, :background_slug] do
    draft
    |> Map.put(field, slug)
    |> Map.put(:errors, [])
    |> prune()
    |> clear_spread_if(field == :background_slug)
  end

  def put_selection(draft, :species, slug), do: put_selection(draft, :species_slug, slug)
  def put_selection(draft, :class, slug), do: put_selection(draft, :class_slug, slug)
  def put_selection(draft, :background, slug), do: put_selection(draft, :background_slug, slug)

  defp clear_spread_if(draft, false), do: draft
  defp clear_spread_if(draft, true), do: %{draft | spread: nil}

  defp prune(%__MODULE__{} = draft) do
    open = draft |> open_choices() |> MapSet.new(& &1.key)

    offered_skills =
      case Enum.find(open_choices(draft), &(&1.key == :class_skills)) do
        nil -> MapSet.new()
        %{choice: choice} -> MapSet.new(choice.from)
      end

    %{
      draft
      | choices: Map.filter(draft.choices, fn {key, _} -> MapSet.member?(open, key) end),
        skill_picks: Enum.filter(draft.skill_picks, &MapSet.member?(offered_skills, &1))
    }
  end

  @shapes [
    [15, 14, 13, 12, 10, 8],
    [15, 15, 13, 12, 8, 8],
    [14, 14, 14, 12, 10, 8],
    [15, 14, 14, 10, 10, 8],
    [14, 14, 13, 12, 12, 8]
  ]

  @doc """
  A starting spread for this draft: every point spent, weighted towards what
  the chosen class actually runs on.

  Players should not have to know that a wizard wants Intelligence before they
  are allowed to make one. This picks a legal full-budget shape at random and
  pours it onto the abilities in the order this class cares about them, so the
  abilities step opens on something playable that can then be adjusted.

  The shapes are all worth exactly `Srd.Rules.PointBuy.budget/0`, so any of
  them is a complete spend rather than a suggestion the player has to finish.
  """
  @spec roll(t()) :: t()
  def roll(%__MODULE__{} = draft) do
    put_shape(draft, Enum.random(@shapes), Enum.shuffle(spare_abilities(draft)))
  end

  @doc """
  The same idea without the dice: the canonical shape on the class's priority
  order, every time.

  Generation uses this rather than `roll/1` so that completing the same draft
  twice produces the same character. Randomness is for the player in front of
  the dialog, not for seeds and fixtures.
  """
  @spec default_bought(t()) :: t()
  def default_bought(%__MODULE__{} = draft) do
    put_shape(draft, hd(@shapes), spare_abilities(draft))
  end

  defp put_shape(%__MODULE__{} = draft, shape, spare) do
    bought = (ranked_abilities(draft) ++ spare) |> Enum.zip(shape) |> Map.new()

    %{draft | bought: bought, errors: []}
  end

  defp ranked_abilities(%__MODULE__{} = draft) do
    case draft.class_slug && Classes.get(draft.class_slug) do
      nil -> []
      class -> Enum.uniq(elem(class.primary_ability, 1) ++ [:con] ++ class.saving_throws)
    end
  end

  defp spare_abilities(%__MODULE__{} = draft), do: Ability.all() -- ranked_abilities(draft)

  @doc """
  Raise one ability by a point, if the budget covers the next step.

  A refused increase is a no-op rather than an error: the button that sends it
  is already disabled, so arriving here means something forged it.
  """
  @spec increase(t(), Ability.t()) :: t()
  def increase(%__MODULE__{} = draft, ability) do
    if PointBuy.can_increase?(draft.bought, ability) do
      %{draft | bought: Map.update!(draft.bought, ability, &(&1 + 1)), errors: []}
    else
      draft
    end
  end

  @doc """
  Lower one ability by a point, refunding it, unless it is already at the floor.
  """
  @spec decrease(t(), Ability.t()) :: t()
  def decrease(%__MODULE__{} = draft, ability) do
    if PointBuy.can_decrease?(draft.bought, ability) do
      %{draft | bought: Map.update!(draft.bought, ability, &(&1 - 1)), errors: []}
    else
      draft
    end
  end

  @doc """
  Points left to spend, or `0` before anything has been bought.
  """
  @spec points_remaining(t()) :: integer()
  def points_remaining(%__MODULE__{bought: bought}) when map_size(bought) == 0,
    do: PointBuy.budget()

  def points_remaining(%__MODULE__{} = draft) do
    case PointBuy.remaining(draft.bought) do
      {:ok, left} -> left
      :error -> 0
    end
  end

  @doc """
  Set how the background's ability score increases are spread.
  """
  @spec put_spread(t(), spread()) :: t()
  def put_spread(%__MODULE__{} = draft, spread), do: %{draft | spread: spread, errors: []}

  @doc """
  The check modifier the character would have for a skill, as the dialog shows
  it: the keying ability's modifier, plus the proficiency bonus when they are
  proficient.

  Returns `nil` until the ability scores exist, because a modifier computed
  from a half-bought spread would be wrong rather than merely incomplete.
  """
  @spec skill_modifier(t(), atom(), keyword()) :: integer() | nil
  def skill_modifier(%__MODULE__{} = draft, skill, opts \\ []) do
    case scores(draft) do
      scores when map_size(scores) == 0 ->
        nil

      scores ->
        ability = Skill.ability(skill)
        modifier = Ability.modifier(Map.fetch!(scores, ability))

        Skill.check_modifier(modifier, Proficiency.bonus(1),
          proficient?: Keyword.get(opts, :proficient?, false)
        )
    end
  end

  @doc """
  The six ability scores the draft comes to: what was bought, plus the
  background's increases.

  Returns `%{}` before anything is bought, because a partial score is more
  misleading than none. Background increases are not subject to the point-buy
  ceiling, so these can and should exceed it.
  """
  @spec scores(t()) :: %{Ability.t() => pos_integer()}
  def scores(%__MODULE__{bought: bought}) when map_size(bought) == 0, do: %{}

  def scores(%__MODULE__{} = draft) do
    Enum.reduce(increases(draft), draft.bought, fn {ability, bump}, scores ->
      Map.update(scores, ability, bump, &(&1 + bump))
    end)
  end

  @doc """
  The background increases the draft's spread comes to, as ability to amount.
  """
  @spec increases(t()) :: %{Ability.t() => pos_integer()}
  def increases(%__MODULE__{spread: nil}), do: %{}
  def increases(%__MODULE__{spread: {:split, larger, smaller}}), do: %{larger => 2, smaller => 1}
  def increases(%__MODULE__{spread: {:even, abilities}}), do: Map.new(abilities, &{&1, 1})

  @doc """
  Toggle a skill among the class' picks, never holding more than it allows.

  Picking past the limit releases the oldest pick rather than refusing, so the
  player's most recent intent always takes effect.
  """
  @spec toggle_skill(t(), atom()) :: t()
  def toggle_skill(%__MODULE__{} = draft, skill) do
    cond do
      skill in draft.skill_picks ->
        %{draft | skill_picks: List.delete(draft.skill_picks, skill), errors: []}

      skill in grants(draft).skills ->
        draft

      true ->
        picks = (draft.skill_picks ++ [skill]) |> Enum.take(-skill_allowance(draft))
        %{draft | skill_picks: picks, errors: []}
    end
  end

  @doc """
  The skills the class offers that the character does not already have.

  Granted skills are excluded rather than merely rejected, so a pick can never
  be spent on a proficiency the background or species already handed over.
  """
  @spec offered_skills(t()) :: [atom()]
  def offered_skills(%__MODULE__{} = draft) do
    case Enum.find(open_choices(draft), &(&1.key == :class_skills)) do
      nil ->
        []

      %{choice: choice} ->
        granted = grants(draft).skills
        Enum.reject(choice.from, &(&1 in granted))
    end
  end

  @doc """
  How many skills the class lets the character choose.
  """
  @spec skill_allowance(t()) :: non_neg_integer()
  def skill_allowance(%__MODULE__{} = draft), do: allowance(draft, :class_skills)

  @doc """
  Toggle an option within one of the keyed choices, never holding more than
  that choice allows. Same release-the-oldest rule as `toggle_skill/2`.
  """
  @spec toggle_choice(t(), Character.choice_key(), term()) :: t()
  def toggle_choice(%__MODULE__{} = draft, key, option) do
    held = Map.get(draft.choices, key, [])
    allowance = allowance(draft, key)

    picks =
      if option in held do
        List.delete(held, option)
      else
        (held ++ [option]) |> Enum.take(-allowance)
      end

    %{draft | choices: Map.put(draft.choices, key, picks), errors: []}
  end

  defp allowance(draft, key) do
    case Enum.find(open_choices(draft), &(&1.key == key)) do
      nil -> 0
      %{choice: choice} -> choice.choose
    end
  end

  @doc """
  The selections in the shape `Srd.Character` takes.
  """
  @spec selections(t()) :: Character.selections()
  def selections(%__MODULE__{} = draft) do
    %{
      species: draft.species_slug,
      class: draft.class_slug,
      background: draft.background_slug,
      level: 1
    }
  end

  @doc """
  Every decision the draft's selections leave open.

  Empty when a slug names content that does not exist, so a caller mid-edit
  never has to rescue.
  """
  @spec open_choices(t()) :: [Character.open_choice()]
  def open_choices(%__MODULE__{} = draft) do
    Character.choices(selections(draft))
  rescue
    ArgumentError -> []
  end

  @doc """
  What the draft's selections grant outright, with nothing to choose.
  """
  @spec grants(t()) :: Character.grants()
  def grants(%__MODULE__{} = draft) do
    Character.grants(selections(draft))
  rescue
    ArgumentError -> %{skills: [], saves: [], feats: [], tools: [], features: []}
  end

  @doc """
  The abilities the chosen background's increases may be spent on.

  Read from the background rather than from `Srd.Character.grants/1`: this is
  not something granted, it is the set an increase may go to, and the rules
  package draws that line deliberately.
  """
  @spec raisable_abilities(t()) :: [Ability.t()]
  def raisable_abilities(%__MODULE__{background_slug: nil}), do: []

  def raisable_abilities(%__MODULE__{background_slug: slug}) do
    case Backgrounds.get(slug) do
      nil -> []
      background -> background.ability_scores
    end
  end

  @doc """
  The spreads a background allows, or `[]` when no background is chosen.
  """
  @spec spreads(t()) :: [[pos_integer()]]
  def spreads(%__MODULE__{background_slug: nil}), do: []
  def spreads(%__MODULE__{}), do: Background.spreads()

  @doc """
  Move to a step. Refuses a step whose prerequisites are not met, so the dialog
  cannot be walked out of order.
  """
  @spec put_step(t(), step()) :: t()
  def put_step(%__MODULE__{} = draft, step) when step in @steps do
    if reachable?(draft, step) do
      %{draft | step: step, errors: []} |> roll_if_unbought(step)
    else
      draft
    end
  end

  defp roll_if_unbought(%__MODULE__{bought: bought} = draft, :abilities)
       when map_size(bought) == 0,
       do: roll(draft)

  defp roll_if_unbought(draft, _step), do: draft

  @doc """
  Whether a step can be shown yet: every step before it is complete.
  """
  @spec reachable?(t(), step()) :: boolean()
  def reachable?(%__MODULE__{} = draft, step) do
    @steps
    |> Enum.take_while(&(&1 != step))
    |> Enum.all?(&complete?(draft, &1))
  end

  @doc """
  Whether one step has everything it asks for.

  A step that asks nothing — the specializations step for a dwarf wizard — is
  complete by definition, which is how it comes to be skipped.
  """
  @spec complete?(t(), step()) :: boolean()
  def complete?(%__MODULE__{} = draft, :identity) do
    String.trim(draft.name) != "" and draft.species_slug != nil and
      draft.class_slug != nil and draft.background_slug != nil
  end

  def complete?(%__MODULE__{} = draft, :abilities) do
    PointBuy.legal?(draft.bought) and draft.spread != nil
  end

  def complete?(%__MODULE__{} = draft, :skills) do
    length(draft.skill_picks) == skill_allowance(draft)
  end

  def complete?(%__MODULE__{} = draft, :specializations) do
    draft
    |> open_choices()
    |> Enum.reject(&(&1.key == :class_skills))
    |> Enum.all?(fn open ->
      length(Map.get(draft.choices, open.key, [])) == open.choice.choose
    end)
  end

  def complete?(%__MODULE__{}, :review), do: true

  @doc """
  The first step that is not complete, or `nil` when every one is.

  What the review names when confirm is unavailable, so a player is told which
  step to go back to rather than that something is wrong.
  """
  @spec first_incomplete_step(t()) :: step() | nil
  def first_incomplete_step(%__MODULE__{} = draft) do
    Enum.find(@steps, &(not complete?(draft, &1)))
  end

  @doc """
  Record validation errors for display.
  """
  @spec put_errors(t(), [{atom(), String.t()}]) :: t()
  def put_errors(%__MODULE__{} = draft, errors), do: %{draft | errors: errors}

  @doc """
  Record what the availability check said about the current name.
  """
  @spec put_name_status(t(), name_status()) :: t()
  def put_name_status(%__MODULE__{} = draft, status), do: %{draft | name_status: status}

  @doc """
  The draft in the shape `Srd.Character.derive/1` takes, so the review is
  computed by exactly the function the character sheet uses.

  Expects a **completed** draft: `derive/1` raises on missing ability scores,
  and a draft is incomplete whenever a user story before this one has not
  shipped. `AgenticRealms.World.CharacterGen.complete/1` is what makes one.
  """
  @spec facts(t()) :: Srd.Character.facts()
  def facts(%__MODULE__{} = draft) do
    %{
      species: draft.species_slug,
      class: draft.class_slug,
      background: draft.background_slug,
      size: size(draft),
      level: 1,
      xp: 0,
      abilities: scores(draft),
      skill_proficiencies: skill_proficiencies(draft),
      save_proficiencies: grants(draft).saves
    }
  end

  @doc """
  The draft as a character sheet, in exactly the shape
  `AgenticRealms.World.Stats.for_player/1` returns.

  Expects a **completed** draft. Both this and the real sheet go through
  `Stats.sheet/3`, which is what makes the review and the created character the
  same character rather than two renderings that agree by inspection.
  """
  @spec sheet(t()) :: map()
  def sheet(%__MODULE__{} = draft) do
    AgenticRealms.World.Stats.sheet(facts(draft), String.trim(draft.name))
  end

  @doc """
  Every skill the character will be proficient in: what the selections grant,
  plus the class picks, plus any skill chosen through a feature.
  """
  @spec skill_proficiencies(t()) :: [atom()]
  def skill_proficiencies(%__MODULE__{} = draft) do
    from_choices =
      draft
      |> open_choices()
      |> Enum.filter(&(&1.choice.kind == :skill))
      |> Enum.flat_map(&Map.get(draft.choices, &1.key, []))

    (grants(draft).skills ++ draft.skill_picks ++ from_choices)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Every feat the character will have: the background's origin feat plus any
  chosen through a feature, such as a human's Versatile.
  """
  @spec feat_slugs(t()) :: [String.t()]
  def feat_slugs(%__MODULE__{} = draft) do
    from_choices =
      draft
      |> open_choices()
      |> Enum.filter(&(&1.choice.kind == :feat))
      |> Enum.flat_map(&Map.get(draft.choices, &1.key, []))

    (grants(draft).feats ++ from_choices)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  The chosen lineage slug, or `nil` for a species that offers none.
  """
  @spec lineage_slug(t()) :: String.t() | nil
  def lineage_slug(%__MODULE__{} = draft) do
    case Map.get(draft.choices, :species_lineage, []) do
      [%{slug: slug} | _] -> slug
      [slug | _] when is_binary(slug) -> slug
      _ -> nil
    end
  end

  @doc """
  The character's size: chosen when the species offers more than one, and the
  species' only size otherwise.
  """
  @spec size(t()) :: atom() | nil
  def size(%__MODULE__{species_slug: nil}), do: nil

  def size(%__MODULE__{} = draft) do
    case Map.get(draft.choices, :species_size, []) do
      [size | _] -> size
      [] -> draft.species_slug |> Srd.Content.Species.get() |> only_size()
    end
  end

  defp only_size(nil), do: nil
  defp only_size(%{sizes: [size]}), do: size
  defp only_size(%{sizes: _many}), do: nil

  @doc """
  The picks with no typed home — tools, weapon masteries, feature options —
  keyed for storage as the read model holds them.

  Lineage, size, skills, and feats are excluded: each has a column of its own.
  """
  @spec stored_choices(t()) :: %{String.t() => [String.t()]}
  def stored_choices(%__MODULE__{} = draft) do
    draft
    |> open_choices()
    |> Enum.reject(&(&1.key in [:species_lineage, :species_size, :class_skills]))
    |> Enum.reject(&(&1.choice.kind in [:skill, :feat]))
    |> Enum.flat_map(fn open ->
      case Map.get(draft.choices, open.key, []) do
        [] -> []
        picks -> [{storage_key(open.key), Enum.map(picks, &to_string/1)}]
      end
    end)
    |> Map.new()
  end

  @doc """
  How a choice key is written in the read model's `choices` map.
  """
  @spec storage_key(Character.choice_key()) :: String.t()
  def storage_key({:feature, name}), do: "feature:" <> name
  def storage_key(key) when is_atom(key), do: Atom.to_string(key)

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%CharacterDraft{} = draft, opts) do
      concat([
        "#CharacterDraft<",
        to_doc(
          %{
            step: draft.step,
            name: draft.name,
            species: draft.species_slug,
            class: draft.class_slug,
            background: draft.background_slug
          },
          opts
        ),
        ">"
      ])
    end
  end
end
