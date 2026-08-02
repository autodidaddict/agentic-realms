defmodule Srd.CharacterTest do
  use ExUnit.Case, async: true

  alias Srd.Content.Armors
  alias Srd.Character
  alias Srd.Rules.Skill

  # A Human Fighter with a Soldier background: the character the game generates
  # by default. Scores are the standard array dealt by class priority, plus the
  # background's +2/+1.
  defp facts(overrides \\ []) do
    Enum.into(overrides, %{
      species: "human",
      class: "fighter",
      background: "soldier",
      size: :medium,
      level: 1,
      xp: 0,
      abilities: %{str: 17, dex: 13, con: 15, int: 12, wis: 10, cha: 8},
      skill_proficiencies: [:acrobatics, :athletics, :history, :intimidation, :perception],
      save_proficiencies: [:str, :con],
      armor: nil,
      shield: nil
    })
  end

  defp find(list, key), do: Enum.find(list, &(&1.key == key))

  describe "derive/1 — identity" do
    test "resolves slugs to names" do
      sheet = Character.derive(facts())

      assert sheet.species == %{slug: "human", name: "Human"}
      assert sheet.class == %{slug: "fighter", name: "Fighter"}
      assert sheet.background == %{slug: "soldier", name: "Soldier"}
    end

    test "carries size through and looks up speed" do
      sheet = Character.derive(facts())

      assert sheet.size == :medium
      assert sheet.speed == 30
    end

    test "tolerates a character with no background" do
      sheet = Character.derive(facts(background: nil))

      assert sheet.background == nil
    end

    test "raises for an unknown species" do
      assert_raise ArgumentError, ~r/unknown species: "gnoll"/, fn ->
        Character.derive(facts(species: "gnoll"))
      end
    end

    test "raises for an unknown class" do
      assert_raise ArgumentError, ~r/unknown class: "artificer"/, fn ->
        Character.derive(facts(class: "artificer"))
      end
    end

    test "raises for an unknown background" do
      assert_raise ArgumentError, ~r/unknown background: "pirate"/, fn ->
        Character.derive(facts(background: "pirate"))
      end
    end
  end

  describe "derive/1 — the level 1 default character" do
    setup do
      %{sheet: Character.derive(facts())}
    end

    test "ability scores and modifiers", %{sheet: sheet} do
      assert Enum.map(sheet.abilities, & &1.key) == [:str, :dex, :con, :int, :wis, :cha]

      assert Enum.map(sheet.abilities, &{&1.score, &1.modifier}) == [
               {17, 3},
               {13, 1},
               {15, 2},
               {12, 1},
               {10, 0},
               {8, -1}
             ]

      assert find(sheet.abilities, :str).name == "Strength"
    end

    test "proficiency bonus, armor class, initiative", %{sheet: sheet} do
      assert sheet.proficiency_bonus == 2
      assert sheet.armor_class == 11
      assert sheet.initiative == 1
    end

    test "hitpoints and hit dice", %{sheet: sheet} do
      assert sheet.max_hit_points == 12
      assert sheet.hit_dice == %Srd.Dice.Expr{count: 1, sides: 10, modifier: 0}
    end

    test "experience progress", %{sheet: sheet} do
      assert sheet.experience == %{
               total: 0,
               into_level: 0,
               to_next: 300,
               fraction: 0.0,
               maxed?: false
             }
    end

    test "saving throws", %{sheet: sheet} do
      assert Enum.map(sheet.saves, &{&1.key, &1.modifier, &1.proficient?}) == [
               {:str, 5, true},
               {:dex, 1, false},
               {:con, 4, true},
               {:int, 1, false},
               {:wis, 0, false},
               {:cha, -1, false}
             ]
    end

    test "every skill, with the proficient ones marked", %{sheet: sheet} do
      by_key = Map.new(sheet.skills, &{&1.key, &1})

      expected = %{
        acrobatics: {3, true},
        animal_handling: {0, false},
        arcana: {1, false},
        athletics: {5, true},
        deception: {-1, false},
        history: {3, true},
        insight: {0, false},
        intimidation: {1, true},
        investigation: {1, false},
        medicine: {0, false},
        nature: {1, false},
        perception: {2, true},
        performance: {-1, false},
        persuasion: {-1, false},
        religion: {1, false},
        sleight_of_hand: {1, false},
        stealth: {1, false},
        survival: {0, false}
      }

      for {skill, {modifier, proficient?}} <- expected do
        row = Map.fetch!(by_key, skill)
        assert row.modifier == modifier, "#{skill} modifier"
        assert row.proficient? == proficient?, "#{skill} proficiency"
        assert row.ability == Skill.ability(skill)
      end
    end

    test "passive perception", %{sheet: sheet} do
      assert sheet.passive_perception == 12
    end
  end

  describe "derive/1 — ordering" do
    setup do
      %{sheet: Character.derive(facts())}
    end

    test "abilities and saves are in canonical order", %{sheet: sheet} do
      canonical = [:str, :dex, :con, :int, :wis, :cha]

      assert Enum.map(sheet.abilities, & &1.key) == canonical
      assert Enum.map(sheet.saves, & &1.key) == canonical
    end

    test "skills are alphabetical by display name", %{sheet: sheet} do
      names = Enum.map(sheet.skills, & &1.name)

      assert names == Enum.sort(names)
    end

    test "list lengths are 6, 6 and 18", %{sheet: sheet} do
      assert length(sheet.abilities) == 6
      assert length(sheet.saves) == 6
      assert length(sheet.skills) == 18
    end
  end

  describe "derive/1 — every proficiency band" do
    # Fighter, d10 hit die, Constitution +2: 12 at level 1, +8 per level after.
    # Proficiency rises +2/+3/+4/+5/+6 at levels 1/5/9/13/17.
    @bands [
      {1, 2, 12},
      {5, 3, 44},
      {9, 4, 76},
      {13, 5, 108},
      {17, 6, 140},
      {20, 6, 164}
    ]

    test "proficiency bonus and maximum hitpoints follow the level" do
      for {level, bonus, max_hp} <- @bands do
        sheet = Character.derive(facts(level: level))

        assert sheet.proficiency_bonus == bonus, "level #{level} proficiency"
        assert sheet.max_hit_points == max_hp, "level #{level} hitpoints"
        assert sheet.hit_dice == %Srd.Dice.Expr{count: level, sides: 10, modifier: 0}
      end
    end

    test "proficient saves and skills rise with the bonus" do
      for {level, bonus, _} <- @bands do
        sheet = Character.derive(facts(level: level))

        # Strength +3, proficient.
        assert find(sheet.saves, :str).modifier == 3 + bonus
        assert find(sheet.skills, :athletics).modifier == 3 + bonus

        # Dexterity +1, not proficient — unmoved by level.
        assert find(sheet.saves, :dex).modifier == 1
        assert find(sheet.skills, :stealth).modifier == 1
      end
    end

    test "armor class and initiative do not move with level" do
      for {level, _, _} <- @bands do
        sheet = Character.derive(facts(level: level))

        assert sheet.armor_class == 11
        assert sheet.initiative == 1
      end
    end

    test "at level 20 experience reports as maxed" do
      sheet = Character.derive(facts(level: 20, xp: 400_000))

      assert sheet.experience.maxed?
      assert sheet.experience.to_next == nil
      assert sheet.experience.fraction == 1.0
    end
  end

  describe "derive/1 — other classes" do
    test "a caster derives the same way" do
      sheet =
        Character.derive(
          facts(
            class: "wizard",
            level: 3,
            abilities: %{str: 8, dex: 14, con: 13, int: 17, wis: 12, cha: 10},
            save_proficiencies: [:int, :wis],
            skill_proficiencies: [:arcana, :history]
          )
        )

      assert sheet.class.name == "Wizard"
      # d6 hit die, Constitution +1: 7 at level 1, +5 per level after.
      assert sheet.max_hit_points == 17
      assert sheet.hit_dice == %Srd.Dice.Expr{count: 3, sides: 6, modifier: 0}
      assert sheet.proficiency_bonus == 2
      assert find(sheet.saves, :int).modifier == 5
      assert find(sheet.skills, :arcana).modifier == 5
    end

    test "a species with a different speed" do
      sheet = Character.derive(facts(species: "dwarf"))

      assert sheet.species.name == "Dwarf"
      assert sheet.speed == 30
    end
  end

  describe "derive/1 — armor" do
    test "unarmored is 10 plus Dexterity" do
      assert Character.derive(facts()).armor_class == 11
    end

    test "worn armor routes through the armor class rules" do
      sheet = Character.derive(facts(armor: Armors.get("chain-mail")))

      # Heavy armor ignores Dexterity.
      assert sheet.armor_class == 16
    end

    test "a shield adds its bonus" do
      sheet =
        Character.derive(facts(armor: Armors.get("chain-mail"), shield: Armors.get("shield")))

      assert sheet.armor_class == 18
    end

    test "medium armor caps the Dexterity bonus" do
      sheet =
        Character.derive(
          facts(
            armor: Armors.get("half-plate"),
            abilities: %{str: 17, dex: 18, con: 15, int: 12, wis: 10, cha: 8}
          )
        )

      # Half plate is 15 base, +2 at most from Dexterity.
      assert sheet.armor_class == 17
    end
  end
end
