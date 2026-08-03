defmodule AgenticRealms.World.CharacterDraftTest do
  @moduledoc """
  The in-progress character.

  Pure and DB-free: the draft never touches the repository, which is half the
  reason it can live in a socket and be thrown away.
  """
  use ExUnit.Case, async: true

  alias AgenticRealms.World.CharacterDraft, as: Draft
  alias Srd.Rules.Ability
  alias Srd.Rules.PointBuy

  @spread %{str: 15, dex: 14, con: 13, int: 12, wis: 10, cha: 8}

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
      assert draft.bought == %{}
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

  describe "roll/1" do
    test "spends the whole budget" do
      rolled = Draft.new() |> Draft.put_selection(:class, "wizard") |> Draft.roll()

      assert PointBuy.fully_spent?(rolled.bought)
      assert map_size(rolled.bought) == 6
    end

    test "puts the highest score on what the class runs on" do
      for _ <- 1..25 do
        rolled = Draft.new() |> Draft.put_selection(:class, "wizard") |> Draft.roll()
        best = rolled.bought |> Map.values() |> Enum.max()

        assert rolled.bought.int == best,
               "a wizard's Intelligence should be its highest score, got #{inspect(rolled.bought)}"
      end
    end

    test "works before a class is chosen, so the step is never empty" do
      rolled = Draft.roll(Draft.new())

      assert PointBuy.fully_spent?(rolled.bought)
    end

    test "does not always produce the same spread" do
      spreads =
        for _ <- 1..40 do
          Draft.new()
          |> Draft.put_selection(:class, "fighter")
          |> Draft.roll()
          |> Map.get(:bought)
        end

      assert length(Enum.uniq(spreads)) > 1, "rolling should vary"
    end
  end

  describe "increase/2 and decrease/2" do
    test "a point is spent and refunded" do
      draft = %{Draft.new() | bought: %{@spread | cha: 8}}

      raised = Draft.increase(draft, :cha)
      assert raised.bought.cha == 8, "the budget is already fully spent"

      freed = draft |> Draft.decrease(:str) |> Draft.increase(:cha)
      assert freed.bought.str == 14
      assert freed.bought.cha == 9
    end

    test "refuses to go above the ceiling or below the floor" do
      draft = %{Draft.new() | bought: Map.new(Ability.all(), &{&1, 8})}

      assert Draft.decrease(draft, :str).bought.str == 8

      maxed = %{draft | bought: %{draft.bought | str: 15}}
      assert Draft.increase(maxed, :str).bought.str == 15
    end

    test "refuses an increase the remaining points will not cover" do
      tight = %{Draft.new() | bought: %{@spread | wis: 9, cha: 8}}

      assert Draft.points_remaining(tight) == 1
      assert Draft.increase(tight, :con).bought.con == 13, "cannot afford the double step"
      assert Draft.increase(tight, :cha).bought.cha == 9, "can afford a single step"
    end

    test "an unknown ability is a no-op rather than a crash" do
      draft = %{Draft.new() | bought: @spread}

      assert Draft.increase(draft, :luck) == draft
      assert Draft.decrease(draft, :luck) == draft
    end
  end

  describe "points_remaining/1" do
    test "is the whole budget before anything is bought" do
      assert Draft.points_remaining(Draft.new()) == PointBuy.budget()
    end

    test "is zero for a spread that spends it all" do
      assert Draft.points_remaining(%{Draft.new() | bought: @spread}) == 0
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
      draft =
        identity()
        |> Draft.toggle_skill(:acrobatics)
        |> Draft.toggle_skill(:perception)
        |> Draft.toggle_skill(:survival)

      assert draft.skill_picks == [:perception, :survival]
    end

    test "a granted skill is refused rather than spent" do
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

      assert Draft.skill_modifier(draft, :acrobatics) == 2
      assert Draft.skill_modifier(draft, :acrobatics, proficient?: true) == 4
    end

    test "includes the background increase" do
      draft = identity() |> with_abilities()

      assert Draft.skill_modifier(draft, :athletics) == 3
    end
  end

  describe "toggle_choice/3" do
    test "never holds more than the choice allows" do
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
      assert Draft.open_choices(identity("dwarf", "wizard", "sage"))
             |> Enum.map(& &1.key) == [:class_skills]

      assert Draft.complete?(identity("dwarf", "wizard", "sage"), :specializations)
    end

    test "a background's tool counts as a specialization when it is a real choice" do
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

  defp full_array, do: with_array(Draft.new())

  defp with_array(draft), do: %{draft | bought: @spread}

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
