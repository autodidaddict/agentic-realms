defmodule AgenticRealms.World.PlayerTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Player
  alias AgenticRealms.World.Commands.{SpawnPlayer, MovePlayer}
  alias AgenticRealms.World.Events.{PlayerSpawned, PlayerMoved}

  @atrium "00000000-0000-0000-0000-000000000001"
  @library "00000000-0000-0000-0000-000000000002"

  defp spawned do
    Player.apply(%Player{}, %PlayerSpawned{player_id: 1, room_id: @atrium})
  end

  describe "SpawnPlayer" do
    test "spawns into the starting room" do
      assert %PlayerSpawned{player_id: 1, room_id: @atrium} =
               Player.execute(%Player{}, %SpawnPlayer{
                 player_id: 1,
                 starting_room_id: @atrium
               })
    end

    test "rejects re-spawning an already-spawned player" do
      assert {:error, :already_spawned} =
               Player.execute(spawned(), %SpawnPlayer{
                 player_id: 1,
                 starting_room_id: @atrium
               })
    end
  end

  describe "MovePlayer" do
    test "moves when from_room_id matches current room" do
      assert %PlayerMoved{
               player_id: 1,
               from_room_id: @atrium,
               to_room_id: @library,
               direction: :east
             } =
               Player.execute(spawned(), %MovePlayer{
                 player_id: 1,
                 from_room_id: @atrium,
                 to_room_id: @library,
                 direction: :east
               })
    end

    test "rejects when player hasn't spawned" do
      assert {:error, :not_spawned} =
               Player.execute(%Player{}, %MovePlayer{
                 player_id: 1,
                 from_room_id: @atrium,
                 to_room_id: @library,
                 direction: :east
               })
    end

    test "rejects when from_room_id is stale" do
      assert {:error, :stale_from_room} =
               Player.execute(spawned(), %MovePlayer{
                 player_id: 1,
                 from_room_id: @library,
                 to_room_id: @atrium,
                 direction: :west
               })
    end
  end

  describe "apply/2" do
    test "PlayerSpawned initializes current_room_id" do
      state = Player.apply(%Player{}, %PlayerSpawned{player_id: 7, room_id: @atrium})
      assert state.id == 7
      assert state.current_room_id == @atrium
    end

    test "PlayerMoved updates current_room_id" do
      state =
        spawned()
        |> Player.apply(%PlayerMoved{
          player_id: 1,
          from_room_id: @atrium,
          to_room_id: @library,
          direction: :east
        })

      assert state.current_room_id == @library
    end
  end
end
