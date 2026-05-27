defmodule AgenticRealms.World.PlayerTest do
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Player
  alias AgenticRealms.World.Commands.{SpawnPlayer, MovePlayer, RecordRoomDiscovery}
  alias AgenticRealms.World.Events.{PlayerSpawned, PlayerMoved, PlayerDiscoveredRoom}

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

  # --- Feature 012 — discovery ---

  describe "RecordRoomDiscovery" do
    test "first call on a fresh aggregate emits PlayerDiscoveredRoom" do
      cmd = %RecordRoomDiscovery{player_id: 1, room_id: @atrium}
      result = Player.execute(spawned(), cmd)

      assert %PlayerDiscoveredRoom{
               player_id: 1,
               room_id: @atrium,
               discovered_at: %DateTime{}
             } = result
    end

    test "second call with the same room is :ok with no event" do
      state =
        spawned()
        |> Player.apply(%PlayerDiscoveredRoom{
          player_id: 1,
          room_id: @atrium,
          discovered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert :ok = Player.execute(state, %RecordRoomDiscovery{player_id: 1, room_id: @atrium})
    end

    test "second call with a DIFFERENT room emits another event" do
      state =
        spawned()
        |> Player.apply(%PlayerDiscoveredRoom{
          player_id: 1,
          room_id: @atrium,
          discovered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert %PlayerDiscoveredRoom{room_id: @library} =
               Player.execute(state, %RecordRoomDiscovery{player_id: 1, room_id: @library})
    end

    test "apply/2 of PlayerDiscoveredRoom adds the room to discovered_room_ids" do
      state =
        Player.apply(spawned(), %PlayerDiscoveredRoom{
          player_id: 1,
          room_id: @atrium,
          discovered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert MapSet.member?(state.discovered_room_ids, @atrium)
    end

    test "rehydration from event stream rebuilds the discovered set" do
      events = [
        %PlayerSpawned{player_id: 1, room_id: @atrium},
        %PlayerDiscoveredRoom{
          player_id: 1,
          room_id: @atrium,
          discovered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        %PlayerDiscoveredRoom{
          player_id: 1,
          room_id: @library,
          discovered_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      ]

      state = Enum.reduce(events, %Player{}, &Player.apply(&2, &1))

      assert MapSet.size(state.discovered_room_ids) == 2
      assert MapSet.member?(state.discovered_room_ids, @atrium)
      assert MapSet.member?(state.discovered_room_ids, @library)
    end
  end
end
