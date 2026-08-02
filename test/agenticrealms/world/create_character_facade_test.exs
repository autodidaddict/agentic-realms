defmodule AgenticRealms.World.CreateCharacterFacadeTest do
  @moduledoc """
  Feature 021 — `Commands.create_character/2`: complete, validate, check the
  name, create.

  The first step is the one worth testing hardest. A draft only carries the
  choices a shipped user story asked for, so while later stories are unshipped
  it arrives incomplete — and completing it is what makes it a legal character.
  Without that step nothing could be created until every step of the dialog
  existed.
  """
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.CharacterDraft, as: Draft
  alias AgenticRealms.World.CharacterGen
  alias AgenticRealms.World.Commands
  alias AgenticRealms.World.Schemas.PlayerState

  defp register do
    suffix = System.unique_integer([:positive])
    {:ok, p} = Accounts.register_player(%{username: "facade_#{suffix}", password: "pw12345678"})
    p.id
  end

  # The US1 shape: a name and three selections, nothing else. This is what the
  # dialog produces until stories 2 through 4 ship.
  defp identity_draft(name, species \\ "human", class \\ "fighter", background \\ "soldier") do
    Draft.new()
    |> Draft.put_name(name)
    |> Draft.put_selection(:species, species)
    |> Draft.put_selection(:class, class)
    |> Draft.put_selection(:background, background)
  end

  defp row(player_id), do: Repo.get(PlayerState, player_id)

  # Error keys may be tuples (a feature choice), so `Keyword.has_key?/2` is out.
  defp error_on?(errors, field), do: Enum.any?(errors, fn {key, _} -> key == field end)

  describe "completion" do
    test "a draft carrying only identity becomes a legal character" do
      player_id = register()

      assert {:ok, :created} = Commands.create_character(player_id, identity_draft("Gandalf"))

      ps = row(player_id)

      assert ps.character_name == "Gandalf"
      assert ps.species_slug == "human"
      assert ps.class_slug == "fighter"
      assert ps.background_slug == "soldier"

      # Everything the player was not asked, filled in and legal.
      assert Enum.sort([ps.str, ps.dex, ps.con, ps.int, ps.wis, ps.cha]) ==
               Enum.sort([17, 13, 15, 12, 10, 8])

      assert length(ps.skill_proficiencies) > 0
      assert ps.save_proficiencies == ["con", "str"]
      assert ps.size == "medium"
    end

    test "it is deterministic" do
      a = register()
      b = register()

      assert {:ok, :created} = Commands.create_character(a, identity_draft("Alpha"))
      assert {:ok, :created} = Commands.create_character(b, identity_draft("Beta"))

      one = row(a)
      two = row(b)

      assert {one.str, one.dex, one.con} == {two.str, two.dex, two.con}
      assert one.skill_proficiencies == two.skill_proficiencies
    end

    test "a choice the player did make is not overwritten" do
      player_id = register()

      draft =
        identity_draft("Legolas", "elf")
        |> Draft.toggle_choice(:species_lineage, "wood-elf")
        |> Draft.toggle_skill(:survival)
        |> Draft.toggle_skill(:acrobatics)

      assert {:ok, :created} = Commands.create_character(player_id, draft)

      ps = row(player_id)

      assert ps.lineage_slug == "wood-elf"
      assert "survival" in ps.skill_proficiencies
      assert "acrobatics" in ps.skill_proficiencies
    end

    test "a player-assigned ability array survives completion" do
      player_id = register()

      draft =
        [str: 8, dex: 10, con: 12, int: 13, wis: 14, cha: 15]
        |> Enum.reduce(identity_draft("Bard"), fn {ability, value}, acc ->
          Draft.assign_ability(acc, ability, value)
        end)

      assert {:ok, :created} = Commands.create_character(player_id, draft)

      ps = row(player_id)

      # Soldier raises str and dex or con; the base 8 in Strength is the
      # player's, not generation's.
      assert ps.str < 12
      assert ps.cha == 15
    end

    test "CharacterGen.complete/1 fills nothing a fully-answered draft already has" do
      draft =
        identity_draft("Complete", "dwarf", "wizard", "sage")
        |> Draft.assign_ability(:int, 15)
        |> Draft.assign_ability(:con, 14)
        |> Draft.assign_ability(:dex, 13)
        |> Draft.assign_ability(:wis, 12)
        |> Draft.assign_ability(:cha, 10)
        |> Draft.assign_ability(:str, 8)
        |> Draft.put_spread({:even, [:con, :int, :wis]})
        |> Draft.toggle_skill(:investigation)
        |> Draft.toggle_skill(:insight)

      assert CharacterGen.complete(draft) == draft
    end
  end

  describe "names" do
    test "a name another character holds is refused" do
      first = register()
      second = register()

      assert {:ok, :created} = Commands.create_character(first, identity_draft("Gandalf"))
      assert {:error, :name_taken} = Commands.create_character(second, identity_draft("Gandalf"))
    end

    test "the match ignores case" do
      first = register()
      second = register()

      assert {:ok, :created} = Commands.create_character(first, identity_draft("Aragorn"))
      assert {:error, :name_taken} = Commands.create_character(second, identity_draft("aragorn"))
      assert {:error, :name_taken} = Commands.create_character(second, identity_draft("ARAGORN"))
    end

    test "the match ignores surrounding whitespace" do
      first = register()
      second = register()

      assert {:ok, :created} = Commands.create_character(first, identity_draft("Boromir"))

      assert {:error, :name_taken} =
               Commands.create_character(second, identity_draft("  boromir  "))
    end

    test "a refused name writes nothing to the player's stream" do
      first = register()
      second = register()

      assert {:ok, :created} = Commands.create_character(first, identity_draft("Gimli"))
      assert {:error, :name_taken} = Commands.create_character(second, identity_draft("Gimli"))

      refute Commands.has_character?(second)
      assert row(second) == nil
    end

    test "the name is stored as typed" do
      player_id = register()

      assert {:ok, :created} = Commands.create_character(player_id, identity_draft("  ArWeN  "))
      assert row(player_id).character_name == "ArWeN"
    end
  end

  describe "validation" do
    test "an invalid draft dispatches nothing at all" do
      player_id = register()
      draft = identity_draft("")

      assert {:error, errors} = Commands.create_character(player_id, draft)
      assert is_list(errors)
      assert error_on?(errors, :name)
      assert row(player_id) == nil
    end

    test "a draft with no class is refused rather than guessed at" do
      player_id = register()
      draft = Draft.new() |> Draft.put_name("Nameless") |> Draft.put_selection(:species, "human")

      assert {:error, errors} = Commands.create_character(player_id, draft)
      assert error_on?(errors, :class_slug)
      assert row(player_id) == nil
    end

    test "a forged pick is refused" do
      player_id = register()

      draft =
        identity_draft("Forger")
        |> Map.put(:choices, %{{:feature, "Fighting Style"} => ["telekinesis"]})

      assert {:error, errors} = Commands.create_character(player_id, draft)
      assert error_on?(errors, {:feature, "Fighting Style"})
      assert row(player_id) == nil
    end
  end

  describe "one character per player" do
    test "a second creation does not make a second character" do
      player_id = register()

      assert {:ok, :created} = Commands.create_character(player_id, identity_draft("First"))
      first = row(player_id)

      # The aggregate's guard: a character is made once.
      Commands.create_character(player_id, identity_draft("Second"))

      assert row(player_id).character_name == first.character_name
      assert row(player_id).species_slug == first.species_slug
    end
  end

  describe "has_character?/1" do
    test "is false before creation and true after" do
      player_id = register()

      refute Commands.has_character?(player_id)
      assert {:ok, :created} = Commands.create_character(player_id, identity_draft("Elrond"))
      assert Commands.has_character?(player_id)
    end
  end
end
