defmodule AgenticRealms.World.StatsSheetTest do
  @moduledoc """
  `Stats.for_player/1` is an adapter over `Srd.Character.derive/1`.

  These assert the adapter: that it reads the row, passes level and scores
  through, and merges in the name and current hitpoints. That the derived
  numbers are *SRD-correct* is proven in the package, in
  `packages/srd_5e/test/srd/character_test.exs`.
  """
  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealms.DataCase
  alias AgenticRealms.World.Stats
  alias AgenticRealms.World.Schemas.PlayerState

  defp register_player(name) do
    suffix = System.unique_integer([:positive])
    {:ok, p} = Accounts.register_player(%{username: "#{name}_#{suffix}", password: "pw12345678"})
    p
  end

  defp with_character(player, overrides \\ []) do
    Repo.insert!(
      struct!(PlayerState, [player_id: player.id] ++ DataCase.character_columns(overrides))
    )

    player
  end

  describe "a freshly created character" do
    setup do
      player = register_player("newbie") |> with_character()
      %{player: player, sheet: Stats.for_player(player.id)}
    end

    test "carries the character's name, not the account's", %{player: player, sheet: sheet} do
      assert sheet.name == AgenticRealms.World.CharacterGen.default().character_name
      refute sheet.name == player.username
    end

    test "identity comes back resolved, not as slugs", %{sheet: sheet} do
      assert sheet.species == %{slug: "human", name: "Human"}
      assert sheet.class == %{slug: "fighter", name: "Fighter"}
      assert sheet.background == %{slug: "soldier", name: "Soldier"}
      assert sheet.size == :medium
      assert sheet.speed == 30
    end

    test "vitals and derived combat values", %{sheet: sheet} do
      assert sheet.level == 1
      assert sheet.hp == %{cur: 12, max: 12}
      assert sheet.proficiency_bonus == 2
      assert sheet.armor_class == 11
      assert sheet.initiative == 1
      assert sheet.passive_perception == 12
      assert sheet.hit_dice == %Srd.Dice.Expr{count: 1, sides: 10, modifier: 0}
    end

    test "experience progress is against the SRD table", %{sheet: sheet} do
      assert sheet.xp == %{
               total: 0,
               into_level: 0,
               to_next: 300,
               fraction: 0.0,
               maxed?: false
             }
    end

    test "all six abilities, all six saves, all eighteen skills", %{sheet: sheet} do
      assert length(sheet.abilities) == 6
      assert length(sheet.saves) == 6
      assert length(sheet.skills) == 18

      assert Enum.map(sheet.abilities, & &1.name) ==
               ["Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"]
    end

    test "proficiency is marked on the granted skills and saves", %{sheet: sheet} do
      proficient = for s <- sheet.skills, s.proficient?, do: s.key

      assert Enum.sort(proficient) ==
               [:acrobatics, :athletics, :history, :intimidation, :perception]

      assert for(s <- sheet.saves, s.proficient?, do: s.key) == [:str, :con]
    end

    test "carries no mana", %{sheet: sheet} do
      refute Map.has_key?(sheet, :mana)
      refute Map.has_key?(sheet, :max_mana)
    end

    test "exposes no leftover derivation key", %{sheet: sheet} do
      refute Map.has_key?(sheet, :experience)
    end
  end

  describe "a levelled character" do
    setup do
      player = register_player("veteran") |> with_character(level: 5, xp: 7_000, hp: 30)
      %{sheet: Stats.for_player(player.id)}
    end

    test "level drives the proficiency bonus", %{sheet: sheet} do
      assert sheet.level == 5
      assert sheet.proficiency_bonus == 3
    end

    test "the hitpoint maximum is derived from the level, not the stored value",
         %{sheet: sheet} do
      assert sheet.hp == %{cur: 30, max: 44}
    end

    test "hit dice and proficient modifiers follow the level", %{sheet: sheet} do
      assert sheet.hit_dice == %Srd.Dice.Expr{count: 5, sides: 10, modifier: 0}

      athletics = Enum.find(sheet.skills, &(&1.key == :athletics))
      assert athletics.modifier == 6

      str_save = Enum.find(sheet.saves, &(&1.key == :str))
      assert str_save.modifier == 6
    end

    test "experience progress is inside the right band", %{sheet: sheet} do
      assert sheet.xp.into_level == 500
      assert sheet.xp.to_next == 7_500
      refute sheet.xp.maxed?
    end
  end

  describe "a character at the cap" do
    setup do
      player = register_player("legend") |> with_character(level: 20, xp: 400_000, hp: 164)
      %{sheet: Stats.for_player(player.id)}
    end

    test "reports as fully levelled with no next threshold", %{sheet: sheet} do
      assert sheet.level == 20
      assert sheet.xp.maxed?
      assert sheet.xp.to_next == nil
      assert sheet.xp.fraction == 1.0
      assert sheet.xp.total == 400_000
    end

    test "still derives everything else", %{sheet: sheet} do
      assert sheet.proficiency_bonus == 6
      assert sheet.hp == %{cur: 164, max: 164}
    end
  end

  describe "the stored vocabulary" do
    test "an unknown skill string is rejected, not silently converted" do
      player = register_player("corrupt") |> with_character(skill_proficiencies: ["haggling"])

      assert_raise ArgumentError, ~r/unknown skill: "haggling"/, fn ->
        Stats.for_player(player.id)
      end
    end

    test "an unknown size is rejected" do
      player = register_player("oversized") |> with_character(size: "colossal")

      assert_raise ArgumentError, ~r/unknown size: "colossal"/, fn ->
        Stats.for_player(player.id)
      end
    end

    test "resolves without depending on the atom table being warm" do
      player = register_player("cold") |> with_character()

      assert %{skills: skills} = Stats.for_player(player.id)
      assert length(skills) == 18
    end
  end

  describe "a row with no character" do
    test "raises rather than rendering a plausible blank" do
      player = register_player("unmade")
      Repo.insert!(%PlayerState{player_id: player.id})

      assert_raise RuntimeError, ~r/no character/, fn -> Stats.for_player(player.id) end
    end

    test "raises when there is no row at all" do
      player = register_player("absent")

      assert_raise RuntimeError, ~r/no player_state row/, fn -> Stats.for_player(player.id) end
    end
  end
end
