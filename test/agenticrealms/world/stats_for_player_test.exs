defmodule AgenticRealms.World.StatsForPlayerTest do
  @moduledoc """
  Feature 019 — `Stats.for_player/1` builds the character-sheet shape from the
  `player_state` read model. Inserts rows directly (pure read; the event-source
  path is incidental), mirroring `ExamineTest`.
  """
  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.Stats
  alias AgenticRealms.World.Schemas.PlayerState

  defp register_player(name) do
    suffix = System.unique_integer([:positive])
    {:ok, p} = Accounts.register_player(%{username: "#{name}_#{suffix}", password: "pw12345678"})
    p
  end

  test "a default player row renders the starting sheet" do
    p = register_player("newbie")
    # A freshly spawned player's row carries schema/SQL defaults.
    Repo.insert!(%PlayerState{player_id: p.id})

    sheet = Stats.for_player(p.id)

    assert sheet.name == p.username
    assert sheet.level == 1
    assert sheet.xp == %{into_level: 0, to_next: 100, fraction: 0.0}
    assert sheet.hp == %{cur: 10, max: 10}
    assert sheet.mana == %{cur: 10, max: 10}

    assert Enum.map(sheet.abilities, & &1.name) ==
             ["Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"]

    assert Enum.all?(sheet.abilities, &(&1.value == 12))

    # No mock fields leak into the sheet (SC-002).
    refute Map.has_key?(sheet, :class)
    assert Map.keys(sheet) |> Enum.sort() == [:abilities, :hp, :level, :mana, :name, :xp]
  end

  test "xp and level drive the progress affordance" do
    p = register_player("veteran")
    # 250 xp => level 2 (threshold 100), 150 into the 200-wide band to level 3.
    Repo.insert!(%PlayerState{player_id: p.id, level: 2, xp: 250})

    sheet = Stats.for_player(p.id)

    assert sheet.level == 2
    assert sheet.xp.into_level == 150
    assert sheet.xp.to_next == 200
    assert sheet.xp.fraction == 0.75
  end
end
