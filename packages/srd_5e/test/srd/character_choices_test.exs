defmodule Srd.CharacterChoicesTest do
  @moduledoc """
  `Srd.Character.choices/1` — what a character still has to decide.

  The counterpart to `derive/1`: one says what follows from the choices, this
  says which are still open. The tests below lean on the whole content set
  rather than a fixture, because the function's value is that it never has to
  learn what a fighting style is.
  """
  use ExUnit.Case, async: true

  alias Srd.Character
  alias Srd.Content.Backgrounds
  alias Srd.Content.Choice
  alias Srd.Content.Classes
  alias Srd.Content.Species

  defp keys(selections), do: selections |> Character.choices() |> Enum.map(& &1.key)

  describe "shape" do
    test "every returned choice carries a key, a source, a label, and a Choice" do
      for species <- Species.all(), class <- Classes.all() do
        for open <- Character.choices(%{species: species.slug, class: class.slug}) do
          assert open.source in [:species, :class, :background]
          assert is_binary(open.label) and open.label != ""
          assert %Choice{} = open.choice
          assert open.choice.choose >= 1
          assert open.choice.from != []
          assert is_nil(open.text) or is_binary(open.text)
        end
      end
    end

    test "no returned choice is already settled" do
      for species <- Species.all(), class <- Classes.all(), background <- Backgrounds.all() do
        selections = %{species: species.slug, class: class.slug, background: background.slug}

        for open <- Character.choices(selections) do
          refute Choice.fixed?(open.choice),
                 "#{inspect(open.key)} is fixed and should have been omitted"
        end
      end
    end

    test "keys are unique within one set of selections" do
      for species <- Species.all(), class <- Classes.all(), background <- Backgrounds.all() do
        keys = keys(%{species: species.slug, class: class.slug, background: background.slug})
        assert keys == Enum.uniq(keys)
      end
    end
  end

  describe "species" do
    test "a species offering more than one size asks which" do
      assert :species_size in keys(%{species: "human"})
      assert :species_size in keys(%{species: "tiefling"})
    end

    test "a species with only one size asks nothing about it" do
      for slug <- ~w(dragonborn dwarf elf gnome goliath halfling orc) do
        refute :species_size in keys(%{species: slug}), "#{slug} should not ask for a size"
      end
    end

    test "a species offering a lineage asks for one, labelled with the trait" do
      open = Character.choices(%{species: "elf"}) |> Enum.find(&(&1.key == :species_lineage))

      assert open.label == "Elven Lineage"
      assert open.choice.kind == :lineage
      assert open.choice.choose == 1
      assert length(open.choice.from) == 3
    end

    test "dragonborn offers all ten draconic ancestries" do
      open =
        Character.choices(%{species: "dragonborn"}) |> Enum.find(&(&1.key == :species_lineage))

      assert open.label == "Draconic Ancestry"
      assert length(open.choice.from) == 10
    end

    test "a species with no lineage asks nothing about one" do
      for slug <- ~w(dwarf halfling human orc) do
        refute :species_lineage in keys(%{species: slug}), "#{slug} should not ask for a lineage"
      end
    end

    test "a species feature carrying a choice is asked for by name" do
      assert {:feature, "Keen Senses"} in keys(%{species: "elf"})
      assert {:feature, "Skillful"} in keys(%{species: "human"})
      assert {:feature, "Versatile"} in keys(%{species: "human"})
    end

    test "size comes before lineage, and both before feature choices" do
      assert keys(%{species: "human"}) == [
               :species_size,
               {:feature, "Skillful"},
               {:feature, "Versatile"}
             ]

      assert keys(%{species: "elf"}) == [:species_lineage, {:feature, "Keen Senses"}]
      assert keys(%{species: "tiefling"}) == [:species_size, :species_lineage]
    end
  end

  describe "class" do
    test "every class offers its skill choice" do
      for class <- Classes.all() do
        open =
          Character.choices(%{class: class.slug}) |> Enum.find(&(&1.key == :class_skills))

        assert open, "#{class.slug} should offer a skill choice"
        assert open.choice == class.skill_choice
      end
    end

    test "a class whose tool proficiency is a real choice asks for it" do
      assert :class_tool in keys(%{class: "bard"})
      assert :class_tool in keys(%{class: "monk"})
    end

    test "a class whose tool proficiency is settled does not ask" do
      refute :class_tool in keys(%{class: "druid"})
      refute :class_tool in keys(%{class: "rogue"})
    end

    test "a class with no tool proficiency does not ask" do
      refute :class_tool in keys(%{class: "wizard"})
    end

    test "level 1 class feature choices are asked for by name" do
      assert keys(%{class: "fighter"}) == [
               :class_skills,
               {:feature, "Fighting Style"},
               {:feature, "Weapon Mastery"}
             ]

      assert {:feature, "Divine Order"} in keys(%{class: "cleric"})
      assert {:feature, "Primal Order"} in keys(%{class: "druid"})
      assert {:feature, "Weapon Mastery"} in keys(%{class: "barbarian"})
    end

    test "a class with no level 1 feature choice offers only its skills" do
      assert keys(%{class: "wizard"}) == [:class_skills]
      assert keys(%{class: "sorcerer"}) == [:class_skills]
      assert keys(%{class: "warlock"}) == [:class_skills]
    end
  end

  describe "level" do
    test "a choice the SRD defers is not asked for at level 1" do
      refute {:feature, "Epic Boon"} in keys(%{class: "fighter"})
    end

    test "it is asked for once the level reaches it" do
      assert {:feature, "Epic Boon"} in keys(%{class: "fighter", level: 19})
    end

    test "no level ever asks for a subclass" do
      for class <- Classes.all(), level <- 1..20 do
        for {:feature, name} <- keys(%{class: class.slug, level: level}) do
          refute name =~ ~r/subclass/i,
                 "#{class.slug} asked for #{name} at level #{level}; subclasses are not choices"
        end
      end
    end

    test "level defaults to 1" do
      assert keys(%{class: "fighter"}) == keys(%{class: "fighter", level: 1})
    end
  end

  describe "background" do
    test "a background whose tool is a real choice asks for it" do
      open =
        Character.choices(%{background: "soldier"})
        |> Enum.find(&(&1.key == :background_tool))

      assert open.source == :background
      assert open.choice.kind == :tool
      assert length(open.choice.from) == 4
    end

    test "a background whose tool is settled does not ask" do
      for slug <- ~w(acolyte criminal sage) do
        refute :background_tool in keys(%{background: slug})
      end
    end
  end

  describe "partial selections" do
    test "nothing selected asks nothing" do
      assert Character.choices(%{}) == []
    end

    test "a species alone returns only that species' choices" do
      assert Enum.all?(Character.choices(%{species: "elf"}), &(&1.source == :species))
    end

    test "a class alone returns only that class' choices" do
      assert Enum.all?(Character.choices(%{class: "fighter"}), &(&1.source == :class))
    end

    test "a nil selection is the same as an absent one" do
      assert Character.choices(%{species: "elf", class: nil, background: nil}) ==
               Character.choices(%{species: "elf"})
    end
  end

  describe "sources are ordered species, class, background" do
    test "for a set of selections that offers all three" do
      sources =
        %{species: "human", class: "bard", background: "soldier"}
        |> Character.choices()
        |> Enum.map(& &1.source)
        |> Enum.dedup()

      assert sources == [:species, :class, :background]
    end
  end

  describe "unknown content" do
    test "raises for a species no content matches" do
      assert_raise ArgumentError, fn -> Character.choices(%{species: "hobbit"}) end
    end

    test "raises for a class no content matches" do
      assert_raise ArgumentError, fn -> Character.choices(%{class: "jester"}) end
    end

    test "raises for a background no content matches" do
      assert_raise ArgumentError, fn -> Character.choices(%{background: "influencer"}) end
    end
  end
end
