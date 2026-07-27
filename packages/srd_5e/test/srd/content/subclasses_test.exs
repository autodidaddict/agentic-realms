defmodule Srd.Content.SubclassesTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Classes
  alias Srd.Content.Subclass
  alias Srd.Content.Subclasses

  doctest Srd.Content.Subclasses

  describe "all/0" do
    test "returns the SRD's twelve subclasses" do
      subclasses = Subclasses.all()
      assert length(subclasses) == 12
      assert Enum.all?(subclasses, &match?(%Subclass{}, &1))
    end

    test "every subclass belongs to a real class" do
      for subclass <- Subclasses.all() do
        assert Classes.get(subclass.class), "#{subclass.slug} names unknown class"
      end
    end
  end

  describe "for_class/1" do
    test "every class has exactly one subclass in the SRD" do
      for class <- Classes.all() do
        assert [_one] = Subclasses.for_class(class.slug)
      end
    end

    test "accepts a class struct" do
      assert Subclasses.for_class(Classes.get("rogue")) |> Enum.map(& &1.name) == ["Thief"]
    end

    test "returns an empty list for a class with none" do
      assert Subclasses.for_class("artificer") == []
    end

    test "names match the SRD" do
      names =
        Classes.all()
        |> Enum.sort_by(& &1.slug)
        |> Enum.map(fn class ->
          [subclass] = Subclasses.for_class(class)
          {class.slug, subclass.name}
        end)

      assert names == [
               {"barbarian", "Path of the Berserker"},
               {"bard", "College of Lore"},
               {"cleric", "Life Domain"},
               {"druid", "Circle of the Land"},
               {"fighter", "Champion"},
               {"monk", "Warrior of the Open Hand"},
               {"paladin", "Oath of Devotion"},
               {"ranger", "Hunter"},
               {"rogue", "Thief"},
               {"sorcerer", "Draconic Sorcery"},
               {"warlock", "Fiend Patron"},
               {"wizard", "Evoker"}
             ]
    end
  end

  describe "features" do
    test "none arrive before the class picks a subclass" do
      for subclass <- Subclasses.all() do
        class = Classes.get(subclass.class)
        assert Enum.all?(subclass.features, &(&1.level >= class.subclass_level))
      end
    end

    test "a subclass feature can carry its own choice" do
      hunters_prey =
        Subclasses.get("hunter").features |> Enum.find(&(&1.name == "Hunter's Prey"))

      assert hunters_prey.choice.from == ["Colossus Slayer", "Horde Breaker"]
    end

    test "the champion's extra fighting style expands to the fighting style feats" do
      extra =
        Subclasses.get("champion").features
        |> Enum.find(&(&1.name == "Additional Fighting Style"))

      assert extra.choice.from == [
               "archery",
               "defense",
               "great-weapon-fighting",
               "two-weapon-fighting"
             ]
    end
  end

  describe "fetch!/1" do
    test "raises for an unknown slug" do
      assert_raise KeyError, fn -> Subclasses.fetch!("college-of-swords") end
    end
  end
end
