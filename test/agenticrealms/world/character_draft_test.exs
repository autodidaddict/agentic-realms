defmodule AgenticRealms.World.CharacterDraftTest do
  @moduledoc """
  Feature 021 — the in-progress character.

  Pure and DB-free: the draft never touches the repository, which is half the
  reason it can live in a socket and be thrown away.
  """
  use ExUnit.Case, async: true

  alias AgenticRealms.World.CharacterDraft, as: Draft
  alias Srd.Rules.Ability

  defp identity(species \\ "human", class \\ "fighter", background \\ "soldier") do
    Draft.new()
    |> Draft.put_name("Gandalf")
    |> Draft.put_selection(:species, species)
    |> Draft.put_selection(:class, class)
    |> Draft.put_selection(:background, background)
  end

  describe "new/0" do
    test "starts empty, at the identity step" do
      draft = Draft.new()

      assert draft.step == :identity
      assert draft.name == ""
      assert draft.species_slug == nil
      assert draft.array == %{}
      assert draft.choices == %{}
      assert draft.skill_picks == []
    end
  end

  describe "put_name/2" do
    test "sets the name and resets what the availability check had said" do
      draft = Draft.new() |> Draft.put_name_status(:available) |> Draft.put_name("Aragorn")

      assert draft.name == "Aragorn"
      assert draft.name_status == :unchecked
    end

    test "clears nothing — the name has no dependents" do
      draft = identity() |> Draft.toggle_skill(:acrobatics) |> Draft.put_name("Strider")

      assert draft.skill_picks == [:acrobatics]
      assert draft.species_slug == "human"
    end
  end

  describe "invalidation" do
    test "changing the class clears the skill picks" do
      draft =
        identity("human", "rogue")
        |> Draft.toggle_skill(:sleight_of_hand)
        |> Draft.put_selection(:class, "wizard")

      assert draft.skill_picks == []
      assert draft.name == "Gandalf"
      assert draft.species_slug == "human"
      assert draft.background_slug == "soldier"
    end

    test "changing the class keeps a skill pick the new class also offers" do
      draft =
        identity("human", "rogue")
        |> Draft.toggle_skill(:perception)
        |> Draft.put_selection(:class, "ranger")

      assert draft.skill_picks == [:perception]
    end

    test "changing the class discards that class' feature choices" do
      draft =
        identity("human", "fighter")
        |> Draft.toggle_choice({:feature, "Fighting Style"}, "defense")
        |> Draft.put_selection(:class, "wizard")

      assert draft.choices == %{}
    end

    test "changing the class keeps the species' choices" do
      draft =
        identity("elf", "fighter")
        |> Draft.toggle_choice(:species_lineage, "wood-elf")
        |> Draft.put_selection(:class, "wizard")

      assert Map.has_key?(draft.choices, :species_lineage)
    end

    test "changing the species discards that species' choices" do
      draft =
        identity("elf", "wizard")
        |> Draft.toggle_choice(:species_lineage, "wood-elf")
        |> Draft.put_selection(:species, "dwarf")

      assert draft.choices == %{}
    end

    test "changing the species keeps the class' feature choices" do
      draft =
        identity("elf", "fighter")
        |> Draft.toggle_choice({:feature, "Fighting Style"}, "defense")
        |> Draft.put_selection(:species, "dwarf")

      assert Map.has_key?(draft.choices, {:feature, "Fighting Style"})
    end

    test "changing the background clears the spread and keeps everything else" do
      draft =
        identity()
        |> Draft.put_spread({:split, :str, :con})
        |> Draft.toggle_skill(:acrobatics)
        |> Draft.put_selection(:background, "sage")

      assert draft.spread == nil
      assert draft.skill_picks == [:acrobatics]
      assert draft.name == "Gandalf"
    end
  end

  describe "assign_ability/3" do
    test "assigns a value to an ability" do
      draft = Draft.new() |> Draft.assign_ability(:str, 15)
      assert draft.array == %{str: 15}
    end

    test "assigning a value another ability holds swaps the two" do
      draft =
        Draft.new()
        |> Draft.assign_ability(:str, 15)
        |> Draft.assign_ability(:dex, 14)
        |> Draft.assign_ability(:dex, 15)

      assert draft.array == %{dex: 15, str: 14}
    end

    test "swapping into an empty ability leaves the other one empty rather than duplicated" do
      draft =
        Draft.new()
        |> Draft.assign_ability(:str, 15)
        |> Draft.assign_ability(:dex, 15)

      assert draft.array == %{dex: 15}
    end

    test "re-assigning the value an ability already holds changes nothing" do
      draft = Draft.new() |> Draft.assign_ability(:str, 15) |> Draft.assign_ability(:str, 15)
      assert draft.array == %{str: 15}
    end

    test "a full array stays full through any number of swaps" do
      full =
        [str: 15, dex: 14, con: 13, int: 12, wis: 10, cha: 8]
        |> Enum.reduce(Draft.new(), fn {ability, value}, acc ->
          Draft.assign_ability(acc, ability, value)
        end)

      swapped =
        full
        |> Draft.assign_ability(:cha, 15)
        |> Draft.assign_ability(:wis, 14)
        |> Draft.assign_ability(:str, 13)

      # Six abilities, six values, each used once — the invariant the swap
      # exists to hold.
      assert map_size(swapped.array) == 6
      assert swapped.array |> Map.values() |> Enum.sort() == Enum.sort(Ability.standard_array())
    end
  end

  describe "scores/1 and increases/1" do
    test "no array means no scores, rather than a partial one" do
      assert Draft.scores(Draft.new()) == %{}
    end

    test "the split spread adds two and one" do
      draft = full_array() |> Draft.put_spread({:split, :str, :con})

      assert Draft.increases(draft) == %{str: 2, con: 1}
      assert Draft.scores(draft).str == 17
      assert Draft.scores(draft).con == 14
      assert Draft.scores(draft).dex == 14
    end

    test "the even spread adds one to all three" do
      draft = full_array() |> Draft.put_spread({:even, [:str, :dex, :con]})

      assert Draft.increases(draft) == %{str: 1, dex: 1, con: 1}
      assert Draft.scores(draft).str == 16
    end

    test "no spread means no increases" do
      assert Draft.increases(full_array()) == %{}
      assert Draft.scores(full_array()).str == 15
    end
  end

  describe "toggle_skill/2" do
    test "adds and removes a pick" do
      draft = identity() |> Draft.toggle_skill(:acrobatics)
      assert draft.skill_picks == [:acrobatics]

      assert Draft.toggle_skill(draft, :acrobatics).skill_picks == []
    end

    test "never holds more than the class allows, releasing the oldest" do
      # Fighter chooses 2. Athletics is granted by soldier, so it is refused
      # rather than held — the two that stick are acrobatics and perception.
      draft =
        identity()
        |> Draft.toggle_skill(:acrobatics)
        |> Draft.toggle_skill(:perception)
        |> Draft.toggle_skill(:survival)

      assert draft.skill_picks == [:perception, :survival]
    end

    test "a granted skill is refused rather than spent" do
      # Soldier grants athletics and intimidation.
      draft = identity() |> Draft.toggle_skill(:athletics)

      assert draft.skill_picks == []
    end
  end

  describe "offered_skills/1" do
    test "is the class' list minus what the character already has" do
      offered = Draft.offered_skills(identity())

      assert :acrobatics in offered
      refute :athletics in offered
      refute :intimidation in offered
    end

    test "is empty with no class chosen" do
      assert Draft.offered_skills(Draft.new()) == []
    end

    test "follows the class" do
      wizard = identity("human", "wizard", "soldier") |> Draft.offered_skills()

      assert :arcana in wizard
      refute :acrobatics in wizard
    end
  end

  describe "skill_modifier/3" do
    test "is nil until the ability scores exist" do
      assert Draft.skill_modifier(identity(), :acrobatics) == nil
    end

    test "is the keying ability's modifier, plus proficiency when trained" do
      draft = identity() |> with_abilities()

      # Dexterity 14 → +2. Proficiency at level 1 is +2.
      assert Draft.skill_modifier(draft, :acrobatics) == 2
      assert Draft.skill_modifier(draft, :acrobatics, proficient?: true) == 4
    end

    test "includes the background increase" do
      draft = identity() |> with_abilities()

      # Strength 15 + 2 from the soldier spread = 17 → +3.
      assert Draft.skill_modifier(draft, :athletics) == 3
    end
  end

  describe "toggle_choice/3" do
    test "never holds more than the choice allows" do
      # Fighter's Weapon Mastery chooses 3.
      draft =
        identity()
        |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "longsword")
        |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "greatsword")
        |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "handaxe")
        |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "dagger")

      assert draft.choices[{:feature, "Weapon Mastery"}] ==
               ["greatsword", "handaxe", "dagger"]
    end

    test "a single-pick choice replaces rather than accumulates" do
      draft =
        identity("elf")
        |> Draft.toggle_choice(:species_lineage, "drow")
        |> Draft.toggle_choice(:species_lineage, "wood-elf")

      assert draft.choices[:species_lineage] == ["wood-elf"]
    end
  end

  describe "open_choices/1 and grants/1" do
    test "reflect the current selections" do
      keys = identity("elf", "fighter") |> Draft.open_choices() |> Enum.map(& &1.key)

      assert :species_lineage in keys
      assert {:feature, "Fighting Style"} in keys
    end

    test "are empty rather than raising when a slug names nothing" do
      draft = Draft.new() |> Draft.put_selection(:species, "hobbit")

      assert Draft.open_choices(draft) == []
      assert Draft.grants(draft).skills == []
    end
  end

  describe "step completion" do
    test "identity needs a name and all three selections" do
      refute Draft.complete?(Draft.new(), :identity)
      refute Draft.complete?(Draft.new() |> Draft.put_name("A"), :identity)
      assert Draft.complete?(identity(), :identity)
    end

    test "a name of only whitespace does not complete identity" do
      draft = identity() |> Draft.put_name("   ")
      refute Draft.complete?(draft, :identity)
    end

    test "abilities needs all six assigned and a spread" do
      refute Draft.complete?(identity(), :abilities)
      refute Draft.complete?(with_array(identity()), :abilities)
      assert Draft.complete?(with_abilities(identity()), :abilities)
    end

    test "skills needs exactly the class' allowance" do
      draft = identity()

      refute Draft.complete?(draft, :skills)
      refute Draft.complete?(Draft.toggle_skill(draft, :acrobatics), :skills)

      assert draft
             |> Draft.toggle_skill(:acrobatics)
             |> Draft.toggle_skill(:perception)
             |> Draft.complete?(:skills)
    end

    test "specializations nothing asks for are complete by definition" do
      # Dwarf offers no lineage and no size, wizard has no level 1 feature
      # choice and no tool, and sage's tool is settled. Nothing is left to ask.
      assert Draft.open_choices(identity("dwarf", "wizard", "sage"))
             |> Enum.map(& &1.key) == [:class_skills]

      assert Draft.complete?(identity("dwarf", "wizard", "sage"), :specializations)
    end

    test "a background's tool counts as a specialization when it is a real choice" do
      # Soldier chooses a gaming set from four.
      refute Draft.complete?(identity("dwarf", "wizard", "soldier"), :specializations)

      assert identity("dwarf", "wizard", "soldier")
             |> Draft.toggle_choice(:background_tool, "dice-set")
             |> Draft.complete?(:specializations)
    end

    test "specializations that are asked for are not complete until answered" do
      refute Draft.complete?(identity("elf", "fighter"), :specializations)
    end
  end

  describe "reachable?/2 and first_incomplete_step/1" do
    test "a step is reachable once every step before it is complete" do
      draft = identity()

      assert Draft.reachable?(draft, :identity)
      assert Draft.reachable?(draft, :abilities)
      refute Draft.reachable?(draft, :skills)
    end

    test "put_step refuses an unreachable step" do
      draft = Draft.new() |> Draft.put_step(:review)
      assert draft.step == :identity
    end

    test "names the first step that is not complete" do
      assert Draft.first_incomplete_step(Draft.new()) == :identity
      assert Draft.first_incomplete_step(identity()) == :abilities
      assert Draft.first_incomplete_step(complete_draft()) == nil
    end
  end

  describe "facts/1" do
    test "produce what Srd.Character.derive/1 takes" do
      facts = complete_draft() |> Draft.facts()

      assert facts.species == "human"
      assert facts.class == "fighter"
      assert facts.background == "soldier"
      assert facts.level == 1
      assert facts.xp == 0
      assert map_size(facts.abilities) == 6
      assert facts.save_proficiencies == [:con, :str]

      assert %{} = Srd.Character.derive(facts)
    end

    test "size comes from the species when it offers only one" do
      draft = complete_draft() |> Draft.put_selection(:species, "dwarf")
      assert Draft.size(draft) == :medium
    end

    test "size comes from the choice when the species offers more than one" do
      draft = complete_draft() |> Draft.toggle_choice(:species_size, :small)
      assert Draft.size(draft) == :small
    end
  end

  describe "skill_proficiencies/1 and feat_slugs/1" do
    test "combine grants with picks, deduplicated and sorted" do
      draft = complete_draft()
      skills = Draft.skill_proficiencies(draft)

      # Soldier grants athletics and intimidation.
      assert :athletics in skills
      assert :intimidation in skills
      assert skills == Enum.uniq(skills)
      assert skills == Enum.sort(skills)
    end

    test "feats combine the origin feat with any chosen through a feature" do
      draft =
        complete_draft()
        |> Draft.toggle_choice({:feature, "Versatile"}, "skilled")

      feats = Draft.feat_slugs(draft)

      assert "savage-attacker" in feats
      assert "skilled" in feats
      assert feats == Enum.sort(feats)
    end
  end

  describe "stored_choices/1" do
    test "hold the picks with no column of their own, under stable string keys" do
      stored =
        identity()
        |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "longsword")
        |> Draft.toggle_choice(:background_tool, "dice-set")
        |> Draft.stored_choices()

      assert stored["feature:Weapon Mastery"] == ["longsword"]
      assert stored["background_tool"] == ["dice-set"]
    end

    test "exclude lineage, size, skills, and feats, which have columns" do
      stored =
        identity("elf", "fighter")
        |> Draft.toggle_choice(:species_lineage, "wood-elf")
        |> Draft.toggle_choice({:feature, "Keen Senses"}, :perception)
        |> Draft.toggle_choice({:feature, "Fighting Style"}, "defense")
        |> Draft.stored_choices()

      refute Map.has_key?(stored, "species_lineage")
      refute Map.has_key?(stored, "feature:Keen Senses")
      refute Map.has_key?(stored, "feature:Fighting Style")
    end
  end

  describe "storage_key/1" do
    test "writes a feature key so the feature's name survives the round trip" do
      assert Draft.storage_key({:feature, "Fighting Style"}) == "feature:Fighting Style"
      assert Draft.storage_key(:class_tool) == "class_tool"
    end
  end

  # --- helpers -------------------------------------------------------------

  defp full_array do
    Draft.new()
    |> Draft.assign_ability(:str, 15)
    |> Draft.assign_ability(:dex, 14)
    |> Draft.assign_ability(:con, 13)
    |> Draft.assign_ability(:int, 12)
    |> Draft.assign_ability(:wis, 10)
    |> Draft.assign_ability(:cha, 8)
  end

  defp with_array(draft) do
    Enum.reduce(
      [str: 15, dex: 14, con: 13, int: 12, wis: 10, cha: 8],
      draft,
      fn {ability, value}, acc -> Draft.assign_ability(acc, ability, value) end
    )
  end

  defp with_abilities(draft), do: draft |> with_array() |> Draft.put_spread({:split, :str, :con})

  defp complete_draft do
    identity()
    |> with_abilities()
    |> Draft.toggle_skill(:acrobatics)
    |> Draft.toggle_skill(:perception)
    |> Draft.toggle_choice(:species_size, :medium)
    |> Draft.toggle_choice({:feature, "Skillful"}, :survival)
    |> Draft.toggle_choice({:feature, "Versatile"}, "alert")
    |> Draft.toggle_choice({:feature, "Fighting Style"}, "defense")
    |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "longsword")
    |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "greatsword")
    |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "handaxe")
    |> Draft.toggle_choice(:background_tool, "dice-set")
  end
end
