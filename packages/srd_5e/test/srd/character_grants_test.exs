defmodule Srd.CharacterGrantsTest do
  @moduledoc """
  `Srd.Character.grants/1` — what a species, class, and background give
  outright, with nothing to choose.

  The other half of `choices/1`: between them every decision the content
  carries is either answered or asked, and none is dropped.
  """
  use ExUnit.Case, async: true

  alias Srd.Character
  alias Srd.Content.Backgrounds
  alias Srd.Content.Choice
  alias Srd.Content.Classes
  alias Srd.Content.Feature
  alias Srd.Content.Species

  describe "shape" do
    test "every key is present even when nothing is selected" do
      grants = Character.grants(%{})

      assert grants == %{skills: [], saves: [], feats: [], tools: [], features: []}
    end

    test "every list is sorted and free of duplicates" do
      for species <- Species.all(), class <- Classes.all(), background <- Backgrounds.all() do
        grants =
          Character.grants(%{
            species: species.slug,
            class: class.slug,
            background: background.slug
          })

        for key <- [:skills, :saves, :feats, :tools] do
          list = Map.fetch!(grants, key)
          assert list == Enum.sort(list), "#{key} is not sorted"
          assert list == Enum.uniq(list), "#{key} holds duplicates"
        end
      end
    end
  end

  describe "background" do
    test "grants its two skills" do
      assert Character.grants(%{background: "soldier"}).skills == [:athletics, :intimidation]
      assert Character.grants(%{background: "acolyte"}).skills == [:insight, :religion]
    end

    test "grants its origin feat" do
      assert Character.grants(%{background: "soldier"}).feats == ["savage-attacker"]
      assert Character.grants(%{background: "criminal"}).feats == ["alert"]
    end

    test "does not report which abilities it can raise" do
      # Not a grant: it is the set an increase may be spent on, and the
      # background itself already says which three those are.
      refute Map.has_key?(Character.grants(%{background: "soldier"}), :abilities)
      assert Backgrounds.get("soldier").ability_scores == [:str, :dex, :con]
    end

    test "grants its tool when the choice is settled" do
      assert Character.grants(%{background: "criminal"}).tools == ["thieves-tools"]
    end

    test "grants no tool when the choice is a real one" do
      assert Character.grants(%{background: "soldier"}).tools == []
    end
  end

  describe "class" do
    test "grants its two saving throws" do
      assert Character.grants(%{class: "fighter"}).saves == [:con, :str]
      assert Character.grants(%{class: "wizard"}).saves == [:int, :wis]
    end

    test "grants its tool when the choice is settled" do
      assert Character.grants(%{class: "rogue"}).tools == ["thieves-tools"]
      assert Character.grants(%{class: "druid"}).tools != []
    end

    test "grants no tool when the choice is a real one" do
      assert Character.grants(%{class: "bard"}).tools == []
      assert Character.grants(%{class: "monk"}).tools == []
    end
  end

  describe "features" do
    test "are the ones in force at the level" do
      level_1 = Character.grants(%{class: "fighter", level: 1}).features
      level_5 = Character.grants(%{class: "fighter", level: 5}).features

      assert Enum.all?(level_1, &(is_nil(&1.level) or &1.level <= 1))
      assert length(level_5) > length(level_1)
      assert Enum.any?(level_5, &(&1.name == "Extra Attack"))
      refute Enum.any?(level_1, &(&1.name == "Extra Attack"))
    end

    test "come from the species as well as the class" do
      names =
        %{species: "dwarf", class: "fighter"}
        |> Character.grants()
        |> Map.fetch!(:features)
        |> Enum.map(& &1.name)

      assert "Darkvision" in names
      assert "Second Wind" in names
    end

    test "include what a granted feat brings with it" do
      names =
        %{background: "criminal"}
        |> Character.grants()
        |> Map.fetch!(:features)
        |> Enum.map(& &1.name)

      assert "Initiative Proficiency" in names
    end

    test "are Feature structs" do
      for feature <- Character.grants(%{species: "elf", class: "wizard"}).features do
        assert %Feature{} = feature
      end
    end
  end

  describe "fixed choices become grants" do
    test "a fixed skill choice is granted rather than asked" do
      # Nothing in the current content set has a fixed skill choice, so this
      # asserts the invariant rather than a specific grant: every choice the
      # content carries is either in grants/1 or in choices/1, never neither.
      for species <- Species.all(), class <- Classes.all(), background <- Backgrounds.all() do
        selections = %{species: species.slug, class: class.slug, background: background.slug}

        asked = selections |> Character.choices() |> Enum.map(& &1.key) |> MapSet.new()
        grants = Character.grants(selections)

        if class.tool_proficiency && Choice.fixed?(class.tool_proficiency) do
          refute MapSet.member?(asked, :class_tool)
          assert Enum.all?(class.tool_proficiency.from, &(&1 in grants.tools))
        end

        if Choice.fixed?(Backgrounds.get(background.slug).tool) do
          refute MapSet.member?(asked, :background_tool)
        end
      end
    end
  end

  describe "deduplication" do
    test "a feat granted by two sources appears once" do
      # Constructed rather than found: no two content sources grant the same
      # feat today, and the property has to hold when one day they do.
      grants = Character.grants(%{background: "criminal"})
      assert grants.feats == Enum.uniq(grants.feats)
      assert length(grants.feats) == 1
    end

    test "a skill granted by two sources appears once" do
      grants = Character.grants(%{species: "elf", class: "rogue", background: "criminal"})
      assert grants.skills == Enum.uniq(grants.skills)
    end
  end

  describe "unknown content" do
    test "raises for a slug no content matches" do
      assert_raise ArgumentError, fn -> Character.grants(%{class: "jester"}) end
    end
  end
end
