defmodule AgenticRealms.World.CharacterDraft.ValidatorTest do
  @moduledoc """
  Feature 021 — the guard on the write side.

  The dialog is a client, so these tests care most about what a forged
  submission can get past. Pure and DB-free.
  """
  use ExUnit.Case, async: true

  alias AgenticRealms.World.CharacterDraft, as: Draft
  alias AgenticRealms.World.CharacterDraft.Validator

  defp errors(draft) do
    case Validator.validate(draft) do
      :ok -> []
      {:error, errors} -> errors
    end
  end

  defp fields(draft), do: draft |> errors() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

  describe "a complete draft" do
    test "is accepted" do
      assert Validator.validate(complete()) == :ok
      assert Validator.valid?(complete())
    end

    test "is accepted for a species and class that ask a lot" do
      assert Validator.validate(elf_fighter()) == :ok
    end

    test "is accepted for a species and class that ask nothing extra" do
      draft =
        Draft.new()
        |> Draft.put_name("Balin")
        |> Draft.put_selection(:species, "dwarf")
        |> Draft.put_selection(:class, "wizard")
        |> Draft.put_selection(:background, "sage")
        |> with_abilities({:split, :int, :con})
        |> Draft.toggle_skill(:investigation)
        |> Draft.toggle_skill(:insight)

      assert Validator.validate(draft) == :ok
    end
  end

  describe "an incomplete draft is refused" do
    test "an empty one names every missing field" do
      assert :name in fields(Draft.new())
      assert :species_slug in fields(Draft.new())
      assert :bought in fields(Draft.new())
    end

    test "the validator has no skip-if-empty clause" do
      # The US1 shape: identity only. It is not a legal character, and the
      # validator says so — completing it is the facade's job, not this one's.
      identity_only =
        Draft.new()
        |> Draft.put_name("Gandalf")
        |> Draft.put_selection(:species, "human")
        |> Draft.put_selection(:class, "fighter")
        |> Draft.put_selection(:background, "soldier")

      assert {:error, _} = Validator.validate(identity_only)
      assert :bought in fields(identity_only)
      assert :spread in fields(identity_only)
      assert :skill_picks in fields(identity_only)
    end
  end

  describe "name" do
    test "must not be empty" do
      assert :name in fields(Draft.put_name(complete(), ""))
    end

    test "must not be only whitespace" do
      assert :name in fields(Draft.put_name(complete(), "   "))
    end

    test "must be at most 32 characters after trimming" do
      assert :name in fields(Draft.put_name(complete(), String.duplicate("a", 33)))
      assert :name not in fields(Draft.put_name(complete(), String.duplicate("a", 32)))
    end

    test "surrounding whitespace does not count toward the limit" do
      padded = "  " <> String.duplicate("a", 32) <> "  "
      assert :name not in fields(Draft.put_name(complete(), padded))
    end
  end

  describe "selections" do
    test "each must be present" do
      assert :class_slug in fields(Draft.put_selection(complete(), :class, nil))
    end

    test "each must resolve to real content" do
      forged = %{complete() | species_slug: "hobbit"}
      assert :species_slug in fields(forged)
    end
  end

  describe "ability scores" do
    test "every ability needs one" do
      forged = %{complete() | bought: %{str: 15, dex: 14}}
      assert :bought in fields(forged)
    end

    test "every score must be one the point-buy table sells" do
      forged = %{complete() | bought: %{str: 18, dex: 18, con: 18, int: 18, wis: 18, cha: 18}}
      assert :bought in fields(forged)
    end

    test "a score below the floor is refused as readily as one above the ceiling" do
      forged = %{complete() | bought: %{str: 7, dex: 14, con: 13, int: 12, wis: 10, cha: 8}}
      assert :bought in fields(forged)
    end

    test "the total must fit the budget" do
      # Every score is buyable and the shape looks plausible; it just costs 33.
      forged = %{complete() | bought: %{str: 15, dex: 15, con: 15, int: 12, wis: 8, cha: 8}}

      assert :bought in fields(forged)
    end

    test "spending under the budget is allowed" do
      thrifty = %{complete() | bought: %{str: 12, dex: 12, con: 12, int: 10, wis: 10, cha: 10}}

      refute :bought in fields(thrifty)
    end

    test "no score may exceed 20" do
      # Unreachable through the dialog — point buy tops out at 15 and the
      # largest increase is +2 — so this is asserted against a forged draft.
      forged = %{complete() | bought: %{str: 15, dex: 14, con: 13, int: 12, wis: 10, cha: 8}}
      forged = %{forged | bought: Map.put(forged.bought, :str, 19), spread: {:split, :str, :con}}

      assert :bought in fields(forged)
    end
  end

  describe "the background spread" do
    test "must be chosen" do
      assert :spread in fields(%{complete() | spread: nil})
    end

    test "must be a shape the rules allow" do
      forged = %{complete() | spread: {:even, [:str, :dex, :con, :int]}}
      assert :spread in fields(forged)
    end

    test "may only raise abilities the background names" do
      # Soldier raises str, dex, or con. Charisma is not on offer.
      forged = %{complete() | spread: {:split, :cha, :str}}
      assert :spread in fields(forged)
    end

    test "may not put both increases on one ability" do
      forged = %{complete() | spread: {:split, :str, :str}}
      assert :spread in fields(forged)
    end

    test "accepts the even spread across all three" do
      draft = %{complete() | spread: {:even, [:str, :dex, :con]}}
      assert Validator.validate(draft) == :ok
    end
  end

  describe "skill picks" do
    test "must number exactly what the class allows" do
      assert :skill_picks in fields(%{complete() | skill_picks: [:athletics]})

      assert :skill_picks in fields(%{
               complete()
               | skill_picks: [:athletics, :acrobatics, :history]
             })
    end

    test "must come from the class' own list" do
      # Arcana is not on the fighter's list.
      forged = %{complete() | skill_picks: [:athletics, :arcana]}
      assert :skill_picks in fields(forged)
    end

    test "may not be spent on a skill the background already granted" do
      # Soldier grants athletics and intimidation.
      forged = %{complete() | skill_picks: [:athletics, :intimidation]}
      assert :skill_picks in fields(forged)
    end

    test "may not repeat one skill" do
      forged = %{complete() | skill_picks: [:acrobatics, :acrobatics]}
      assert :skill_picks in fields(forged)
    end
  end

  describe "the generic choice rule" do
    test "each open choice needs exactly its number of picks" do
      forged = put_in(elf_fighter().choices[{:feature, "Weapon Mastery"}], ["longsword"])
      assert {:feature, "Weapon Mastery"} in fields(forged)
    end

    test "a pick must have been among the options" do
      forged = put_in(elf_fighter().choices[{:feature, "Fighting Style"}], ["telekinesis"])
      assert {:feature, "Fighting Style"} in fields(forged)
    end

    test "a lineage must belong to the chosen species" do
      forged = put_in(elf_fighter().choices[:species_lineage], ["forest-gnome"])
      assert :species_lineage in fields(forged)
    end

    test "a key nothing asked for is refused" do
      forged = put_in(complete().choices[{:feature, "Wild Shape"}], ["bear"])
      assert :choices in fields(forged)
    end

    test "an unanswered choice is refused" do
      forged = %{elf_fighter() | choices: Map.delete(elf_fighter().choices, :species_lineage)}
      assert :species_lineage in fields(forged)
    end

    test "the same option twice is refused" do
      forged =
        put_in(elf_fighter().choices[{:feature, "Weapon Mastery"}], [
          "longsword",
          "longsword",
          "longsword"
        ])

      assert {:feature, "Weapon Mastery"} in fields(forged)
    end
  end

  describe "it carries no SRD rules of its own" do
    test "a choice it has never heard of validates by membership alone" do
      # Divine Order is a cleric feature this module names nowhere.
      draft =
        Draft.new()
        |> Draft.put_name("Elrond")
        |> Draft.put_selection(:species, "dwarf")
        |> Draft.put_selection(:class, "cleric")
        |> Draft.put_selection(:background, "acolyte")
        |> with_abilities({:split, :wis, :int})
        |> Draft.toggle_skill(:medicine)
        |> Draft.toggle_skill(:persuasion)

      assert {:feature, "Divine Order"} in fields(draft)

      answered = Draft.toggle_choice(draft, {:feature, "Divine Order"}, "Protector")
      assert Validator.validate(answered) == :ok
    end
  end

  # --- helpers -------------------------------------------------------------

  defp with_abilities(draft, spread) do
    %{draft | bought: %{str: 15, dex: 14, con: 13, int: 12, wis: 10, cha: 8}}
    |> Draft.put_spread(spread)
  end

  # A human fighter: size, Skillful, Versatile, Fighting Style, Weapon Mastery,
  # and soldier's gaming set. Everything answered.
  defp complete do
    Draft.new()
    |> Draft.put_name("Gandalf")
    |> Draft.put_selection(:species, "human")
    |> Draft.put_selection(:class, "fighter")
    |> Draft.put_selection(:background, "soldier")
    |> with_abilities({:split, :str, :con})
    |> Draft.toggle_skill(:acrobatics)
    |> Draft.toggle_skill(:perception)
    |> Draft.toggle_choice(:species_size, :medium)
    |> Draft.toggle_choice({:feature, "Skillful"}, :survival)
    |> Draft.toggle_choice({:feature, "Versatile"}, "skilled")
    |> Draft.toggle_choice({:feature, "Fighting Style"}, "defense")
    |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "longsword")
    |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "greatsword")
    |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "handaxe")
    |> Draft.toggle_choice(:background_tool, "dice-set")
  end

  defp elf_fighter do
    Draft.new()
    |> Draft.put_name("Legolas")
    |> Draft.put_selection(:species, "elf")
    |> Draft.put_selection(:class, "fighter")
    |> Draft.put_selection(:background, "soldier")
    |> with_abilities({:split, :dex, :con})
    |> Draft.toggle_skill(:acrobatics)
    |> Draft.toggle_skill(:history)
    |> Draft.toggle_choice(:species_lineage, "wood-elf")
    |> Draft.toggle_choice({:feature, "Keen Senses"}, :perception)
    |> Draft.toggle_choice({:feature, "Fighting Style"}, "archery")
    |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "longbow")
    |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "shortsword")
    |> Draft.toggle_choice({:feature, "Weapon Mastery"}, "scimitar")
    |> Draft.toggle_choice(:background_tool, "dice-set")
  end
end
