defmodule AgenticRealms.World.CharacterGenTest do
  @moduledoc """
  Feature 020 — deterministic default character generation.

  Generation is policy, not rules: the SRD says a fighter picks two skills from
  a list, and this module decides which two. These tests pin those decisions so
  a change to them is deliberate and visible.

  Pure — no database, no Commanded.
  """
  use ExUnit.Case, async: true

  alias AgenticRealms.World.CharacterGen

  @defaults [
    species: "human",
    class: "fighter",
    background: "soldier",
    size: :medium,
    species_skill: :perception,
    species_feat: "alert"
  ]

  describe "default/1 — the configured Human Fighter" do
    setup do
      %{character: CharacterGen.default(@defaults)}
    end

    test "carries the configured identity", %{character: c} do
      assert c.species_slug == "human"
      assert c.class_slug == "fighter"
      assert c.background_slug == "soldier"
      assert c.size == "medium"
    end

    test "deals the standard array by class priority, then the background's increases",
         %{character: c} do
      # Priority is primary (Strength), then the saving throws (Constitution),
      # then canonical order: 15/14/13/12/10/8 lands as STR/CON/DEX/INT/WIS/CHA.
      # Soldier then adds +2 Strength and +1 Constitution.
      assert c.abilities == %{str: 17, dex: 13, con: 15, int: 12, wis: 10, cha: 8}
    end

    test "takes the class's saving throws", %{character: c} do
      assert c.save_proficiencies == ["con", "str"]
    end

    test "combines background, species and class skills without waste", %{character: c} do
      # Soldier grants Athletics and Intimidation, Human's Skillful trait is
      # configured to Perception, and the Fighter's two picks come from what is
      # left, best modifier first: Acrobatics (+1 Dex) and History (+1 Int).
      assert c.skill_proficiencies == [
               "acrobatics",
               "athletics",
               "history",
               "intimidation",
               "perception"
             ]
    end

    test "records the background's origin feat and the configured species feat",
         %{character: c} do
      assert Enum.sort(c.feat_slugs) == ["alert", "savage-attacker"]
    end

    test "starts at the level 1 hitpoint maximum", %{character: c} do
      # d10 hit die, Constitution +2.
      assert c.max_hp == 12
    end
  end

  describe "default/1 — determinism" do
    test "two calls with the same config are identical" do
      assert CharacterGen.default(@defaults) == CharacterGen.default(@defaults)
    end

    test "skill and save lists are sorted and free of duplicates" do
      c = CharacterGen.default(@defaults)

      for list <- [c.skill_proficiencies, c.save_proficiencies, c.feat_slugs] do
        assert list == Enum.sort(list)
        assert length(Enum.uniq(list)) == length(list)
      end
    end
  end

  describe "default/1 — a different class" do
    setup do
      %{character: CharacterGen.default(Keyword.put(@defaults, :class, "wizard"))}
    end

    test "puts the highest score on that class's primary ability", %{character: c} do
      # Wizard priority: Intelligence, then Wisdom, then canonical order —
      # so INT 15, WIS 14, STR 13, DEX 12, CON 10, CHA 8. Soldier's increases
      # go to the highest-priority of Strength, Dexterity and Constitution.
      assert c.abilities == %{int: 15, wis: 14, str: 15, dex: 13, con: 10, cha: 8}
    end

    test "uses that class's hit die and saving throws", %{character: c} do
      # d6 hit die, Constitution +0.
      assert c.max_hp == 6
      assert c.save_proficiencies == ["int", "wis"]
    end

    test "picks skills from that class's list" do
      c = CharacterGen.default(Keyword.put(@defaults, :class, "wizard"))

      assert "athletics" in c.skill_proficiencies
      assert "intimidation" in c.skill_proficiencies
      assert "perception" in c.skill_proficiencies
      # Two more from the Wizard list, never duplicating what is already held.
      assert length(c.skill_proficiencies) == 5
    end
  end

  describe "default/1 — a different species" do
    test "an species with no Skillful trait still honours the configured skill" do
      c = CharacterGen.default(Keyword.put(@defaults, :species, "dwarf"))

      assert c.species_slug == "dwarf"
      assert "perception" in c.skill_proficiencies
    end
  end

  describe "default/0" do
    test "reads the application configuration" do
      assert CharacterGen.default() == CharacterGen.default(@defaults)
    end
  end
end
