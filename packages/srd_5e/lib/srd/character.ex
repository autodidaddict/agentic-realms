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
  alias Srd.Content.Classes
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
        ArmorClass.compute(Map.get(facts, :armor), modifiers.dex,
          shield: Map.get(facts, :shield)
        ),
      initiative: Initiative.modifier(modifiers.dex),
      passive_perception: Check.passive(modifier_for(skills, :perception)),
      abilities: abilities(scores, modifiers),
      saves: saves(modifiers, bonus, save_proficiencies),
      skills: skills
    }
  end

  # --- sections ------------------------------------------------------------

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

  # --- helpers -------------------------------------------------------------

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
