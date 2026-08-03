defmodule Srd.Character do
  @moduledoc """
  Everything that follows from a character's choices.

  `Srd.Content` answers what a character may be; this answers what a character
  *is*, once those choices are made. Give it the facts — species, class,
  background, level, ability scores, and what it is proficient in — and it
  returns the numbers a character sheet shows: modifiers, proficiency bonus,
  saving throws, skills, passive perception, armor class, initiative, hit
  points, hit dice, and progress toward the next level.

  Like the content layer, it holds no character of its own. There is no struct
  to build and nothing is stored: a map goes in and a map comes out. It is the
  composition over `Srd.Rules`, so a consumer never reimplements the arithmetic
  a sheet needs.

  ```elixir
  Srd.Character.derive(%{
    species: "human", class: "fighter", background: "soldier",
    size: :medium, level: 3, xp: 1_200,
    abilities: %{str: 17, dex: 13, con: 15, int: 12, wis: 10, cha: 8},
    skill_proficiencies: [:athletics, :perception],
    save_proficiencies: [:str, :con]
  })
  ```

  Armor is passed in rather than assumed, so a character with none gets the
  unarmored value and a character in plate gets plate.
  """

  alias Srd.Content.Backgrounds
  alias Srd.Content.Choice
  alias Srd.Content.Classes
  alias Srd.Content.Feats
  alias Srd.Content.Feature
  alias Srd.Content.Species
  alias Srd.Rules.Ability
  alias Srd.Rules.ArmorClass
  alias Srd.Rules.Check
  alias Srd.Rules.Experience
  alias Srd.Rules.Hitpoints
  alias Srd.Rules.Initiative
  alias Srd.Rules.Proficiency
  alias Srd.Rules.Save
  alias Srd.Rules.Skill

  @typedoc """
  What a caller knows about a character. `:background`, `:armor`, and `:shield`
  may be `nil`; everything else is required.
  """
  @type facts :: %{
          required(:species) => String.t(),
          required(:class) => String.t(),
          required(:size) => Species.size(),
          required(:level) => pos_integer(),
          required(:xp) => integer(),
          required(:abilities) => %{Ability.t() => pos_integer()},
          required(:skill_proficiencies) => [Skill.skill()],
          required(:save_proficiencies) => [Ability.t()],
          optional(:background) => String.t() | nil,
          optional(:armor) => map() | nil,
          optional(:shield) => map() | nil
        }

  @doc """
  Derive a character sheet from the facts of a character.

  Ability and saving throw lists come back in the SRD's canonical STR, DEX, CON,
  INT, WIS, CHA order; skills come back alphabetically by display name. Both
  orders are part of the contract, so a caller renders the lists as given.

  Returns `:max_hit_points` rather than a hit point pool: how much damage a
  character has taken is the caller's state, not a derived value. Feed the
  maximum to `Srd.Rules.Hitpoints.new/3` to make a pool.

  Raises `ArgumentError` for a slug no content matches.
  """
  @spec derive(facts()) :: map()
  def derive(%{} = facts) do
    species = fetch_species!(facts.species)
    class = fetch_class!(facts.class)
    background = fetch_background!(Map.get(facts, :background))

    level = facts.level
    scores = facts.abilities
    modifiers = Map.new(Ability.all(), &{&1, Ability.modifier(Map.fetch!(scores, &1))})
    bonus = Proficiency.bonus(level)

    skill_proficiencies = MapSet.new(facts.skill_proficiencies)
    save_proficiencies = MapSet.new(facts.save_proficiencies)
    skills = skills(modifiers, bonus, skill_proficiencies)

    %{
      species: named(species),
      class: named(class),
      background: named(background),
      size: facts.size,
      speed: species.speed,
      level: level,
      proficiency_bonus: bonus,
      experience: experience(facts.xp),
      max_hit_points: Hitpoints.maximum(class.hit_die, level, modifiers.con),
      hit_dice: Hitpoints.hit_dice(class.hit_die, level),
      armor_class:
        ArmorClass.compute(Map.get(facts, :armor), modifiers.dex, shield: Map.get(facts, :shield)),
      initiative: Initiative.modifier(modifiers.dex),
      passive_perception: Check.passive(modifier_for(skills, :perception)),
      abilities: abilities(scores, modifiers),
      saves: saves(modifiers, bonus, save_proficiencies),
      skills: skills
    }
  end

  @typedoc """
  What a caller has settled on so far. Every field is optional, so a builder can
  ask what an elf still has to decide before a class is picked. `:level`
  defaults to 1.
  """
  @type selections :: %{
          optional(:species) => String.t() | nil,
          optional(:class) => String.t() | nil,
          optional(:background) => String.t() | nil,
          optional(:level) => pos_integer()
        }

  @typedoc """
  A decision that is still open:

  * `:key` - a stable identifier, so a caller can address the answer
  * `:source` - which of the three offered it
  * `:label` - what to call it, taken from the content
  * `:text` - the feature's restated mechanics, when it came from a feature
  * `:choice` - the `Srd.Content.Choice` itself
  """
  @type open_choice :: %{
          key: choice_key(),
          source: :species | :class | :background,
          label: String.t(),
          text: String.t() | nil,
          choice: Choice.t()
        }

  @typedoc "How an open choice is addressed."
  @type choice_key ::
          :species_size
          | :species_lineage
          | :class_skills
          | :class_tool
          | :background_tool
          | {:feature, String.t()}

  @doc """
  Every decision the selections leave open at their level.

  The counterpart to `derive/1`. That one says what follows from a character's
  choices; this one says which choices are still to be made, so a builder can
  ask without knowing what it is asking about.

  A choice comes back only if it is genuinely open. One with no more options
  than picks is already settled, so it is a grant rather than a question and
  `grants/1` reports it instead. One the SRD defers to a higher level is not
  returned until the level reaches it, which is why a level 1 character is never
  asked for a subclass.

  Selections may be partial: an absent or `nil` species contributes nothing, and
  `choices(%{})` is `[]`.

  Order is stable and part of the contract — species, then class, then
  background, and within a source the order the content lists them, with a
  species' size and lineage ahead of its features. Render the list as given.

      iex> Srd.Character.choices(%{species: "elf"}) |> Enum.map(& &1.key)
      [:species_lineage, {:feature, "Keen Senses"}]

      iex> Srd.Character.choices(%{class: "fighter"}) |> Enum.map(& &1.key)
      [:class_skills, {:feature, "Fighting Style"}, {:feature, "Weapon Mastery"}]

      iex> Srd.Character.choices(%{species: "dwarf", class: "wizard", background: "sage"})
      ...> |> Enum.map(& &1.key)
      [:class_skills]

  Raises `ArgumentError` for a slug no content matches.
  """
  @spec choices(selections()) :: [open_choice()]
  def choices(%{} = selections) do
    level = Map.get(selections, :level, 1)

    species_choices(selection(selections, :species, &fetch_species!/1), level) ++
      class_choices(selection(selections, :class, &fetch_class!/1), level) ++
      background_choices(selection(selections, :background, &fetch_background!/1))
  end

  defp species_choices(nil, _level), do: []

  defp species_choices(species, level) do
    size =
      offer(:species_size, :species, "Size", nil, %Choice{
        kind: :size,
        choose: 1,
        from: species.sizes
      })

    lineage =
      offer(:species_lineage, :species, species.lineage_trait, nil, %Choice{
        kind: :lineage,
        choose: 1,
        from: species.lineages
      })

    size ++ lineage ++ feature_choices(species.features, :species, level)
  end

  defp class_choices(nil, _level), do: []

  defp class_choices(class, level) do
    skills = offer(:class_skills, :class, "Skill Proficiencies", nil, class.skill_choice)
    tool = offer(:class_tool, :class, "Tool Proficiency", nil, class.tool_proficiency)

    skills ++ tool ++ feature_choices(class.features, :class, level)
  end

  defp background_choices(nil), do: []

  defp background_choices(background) do
    offer(:background_tool, :background, "Tool Proficiency", nil, background.tool)
  end

  defp feature_choices(features, source, level) do
    features
    |> Feature.through_level(level)
    |> Enum.flat_map(fn feature ->
      offer({:feature, feature.name}, source, feature.name, feature.text, feature.choice)
    end)
  end

  defp offer(_key, _source, _label, _text, nil), do: []

  defp offer(key, source, label, text, %Choice{} = choice) do
    if Choice.fixed?(choice) do
      []
    else
      [%{key: key, source: source, label: label, text: text, choice: choice}]
    end
  end

  @typedoc """
  What the selections give outright:

  * `:skills` - skill proficiencies, from the background and any settled choice
  * `:saves` - the class's saving throw proficiencies
  * `:feats` - the background's origin feat
  * `:tools` - tool proficiencies whose choice was already settled
  * `:features` - every feature in force at the level, granted feats included

  Which abilities a background may raise is deliberately absent. It is not
  granted — it is the set an increase may be spent on — and
  `Srd.Content.Backgrounds.get(slug).ability_scores` already says so.
  """
  @type grants :: %{
          skills: [Skill.skill()],
          saves: [Ability.t()],
          feats: [String.t()],
          tools: [String.t()],
          features: [Feature.t()]
        }

  @doc """
  What a species, class, and background grant outright, with nothing to choose.

  The other half of `choices/1`. A choice with no more options than picks is not
  a question, so it is reported here instead; between the two functions every
  decision the content carries is either answered or asked, and none is dropped.

  Every list is deduplicated and sorted, so a feat granted by two sources
  appears once. `:features` keeps content order rather than being sorted,
  because a feature list reads by level.

      iex> Srd.Character.grants(%{background: "soldier"}).skills
      [:athletics, :intimidation]

      iex> Srd.Character.grants(%{class: "fighter"}).saves
      [:con, :str]

  Raises `ArgumentError` for a slug no content matches.
  """
  @spec grants(selections()) :: grants()
  def grants(%{} = selections) do
    level = Map.get(selections, :level, 1)

    species = selection(selections, :species, &fetch_species!/1)
    class = selection(selections, :class, &fetch_class!/1)
    background = selection(selections, :background, &fetch_background!/1)

    feats = sorted(if(background, do: [background.origin_feat], else: []))

    %{
      skills: sorted(settled(:skill, species, class, background)),
      saves: sorted(if(class, do: class.saving_throws, else: [])),
      feats: feats,
      tools: sorted(settled(:tool, species, class, background)),
      features: features_in_force(species, class, feats, level)
    }
  end

  defp settled(:skill, species, class, background) do
    granted = if background, do: background.skills, else: []
    granted ++ settled_options(:skill, species, class, background)
  end

  defp settled(:tool, species, class, background) do
    settled_options(:tool, species, class, background)
  end

  defp settled_options(kind, species, class, background) do
    [
      species && species.features,
      class && class.features,
      class && class.tool_proficiency,
      background && background.tool
    ]
    |> Enum.flat_map(&settled_from/1)
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.flat_map(& &1.from)
  end

  defp settled_from(nil), do: []
  defp settled_from(%Choice{} = choice), do: if(Choice.fixed?(choice), do: [choice], else: [])

  defp settled_from(features) when is_list(features) do
    features
    |> Enum.map(& &1.choice)
    |> Enum.flat_map(&settled_from/1)
  end

  defp features_in_force(species, class, feats, level) do
    feat_features =
      feats
      |> Enum.map(&Feats.get/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(& &1.features)

    [species && species.features, class && class.features]
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&Feature.through_level(&1, level))
    |> Kernel.++(Feature.through_level(feat_features, level))
    |> Enum.uniq()
  end

  defp selection(selections, key, fetch) do
    case Map.get(selections, key) do
      nil -> nil
      slug -> fetch.(slug)
    end
  end

  defp sorted(values), do: values |> Enum.uniq() |> Enum.sort()

  defp abilities(scores, modifiers) do
    for key <- Ability.all() do
      %{
        key: key,
        name: Ability.name(key),
        score: Map.fetch!(scores, key),
        modifier: Map.fetch!(modifiers, key)
      }
    end
  end

  defp saves(modifiers, bonus, proficient) do
    for key <- Ability.all() do
      proficient? = MapSet.member?(proficient, key)

      %{
        key: key,
        name: Ability.name(key),
        modifier: Save.modifier(Map.fetch!(modifiers, key), bonus, proficient?: proficient?),
        proficient?: proficient?
      }
    end
  end

  defp skills(modifiers, bonus, proficient) do
    Skill.all()
    |> Enum.map(fn key ->
      ability = Skill.ability(key)
      proficient? = MapSet.member?(proficient, key)

      %{
        key: key,
        name: Skill.name(key),
        ability: ability,
        modifier:
          Skill.check_modifier(Map.fetch!(modifiers, ability), bonus, proficient?: proficient?),
        proficient?: proficient?
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp experience(xp) do
    xp
    |> Experience.progress()
    |> Map.delete(:level)
    |> Map.put(:total, max(xp, 0))
  end

  defp modifier_for(skills, key) do
    Enum.find_value(skills, fn
      %{key: ^key, modifier: modifier} -> modifier
      _ -> nil
    end)
  end

  defp named(nil), do: nil
  defp named(%{slug: slug, name: name}), do: %{slug: slug, name: name}

  defp fetch_species!(slug) do
    Species.get(slug) || raise(ArgumentError, "unknown species: #{inspect(slug)}")
  end

  defp fetch_class!(slug) do
    Classes.get(slug) || raise(ArgumentError, "unknown class: #{inspect(slug)}")
  end

  defp fetch_background!(nil), do: nil

  defp fetch_background!(slug) do
    Backgrounds.get(slug) || raise(ArgumentError, "unknown background: #{inspect(slug)}")
  end
end
