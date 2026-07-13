defmodule AgenticRealms.World.PlayerSpawnStatsTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Player
  alias AgenticRealms.World.Events.PlayerSpawned

  test "apply(PlayerSpawned) seeds the documented starting stats" do
    state =
      Player.apply(%Player{}, %PlayerSpawned{
        player_id: "p1",
        room_id: "room-1"
      })

    assert state.id == "p1"
    assert state.current_room_id == "room-1"

    assert state.str == 12
    assert state.dex == 12
    assert state.con == 12
    assert state.int == 12
    assert state.wis == 12
    assert state.cha == 12

    assert state.level == 1
    assert state.xp == 0
    assert state.hp == 10
    assert state.max_hp == 10
    assert state.mana == 10
    assert state.max_mana == 10
  end
end
