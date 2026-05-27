defmodule AgenticRealms.World.Ticks.LifecycleTest do
  @moduledoc """
  Tests for the singleton tick Lifecycle GenServer (feature 011).

  Exercises the 0↔1 transition detection on simulated `RoomPlayerArrived`
  and `RoomPlayerLeft` events. Grace periods are configured small in
  `config/test.exs` (join 10 ms, leave 50 ms) so tests run quickly.
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.World.Schemas.Room
  alias AgenticRealms.World.Ticks.{Lifecycle, Registry, Supervisor}
  alias AgenticRealms.World.UIEvents.{RoomPlayerArrived, RoomPlayerLeft}

  defp insert_room do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "T",
      description: ".",
      region_id: AgenticRealms.DataCase.insert_test_region()
    })
  end

  defp synth_arrived(room_id, player_id, carried \\ []) do
    %RoomPlayerArrived{
      room_id: room_id,
      actor_id: player_id,
      actor_username: "u",
      from_direction: nil,
      carried_object_ids: carried
    }
  end

  defp synth_left(room_id, player_id, carried \\ []) do
    %RoomPlayerLeft{
      room_id: room_id,
      actor_id: player_id,
      actor_username: "u",
      to_direction: :north,
      carried_object_ids: carried
    }
  end

  defp join_grace,
    do: Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:join_grace_ms]

  defp leave_grace,
    do: Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:leave_grace_ms]

  describe "0 → ≥1 transition" do
    test "RoomPlayerArrived schedules a join-grace timer and then starts the scheduler" do
      room = insert_room()

      Lifecycle.notify(synth_arrived(room.id, 1))
      # Allow the message to be processed.
      _ = Lifecycle.get_state()

      state = Lifecycle.get_state()
      assert MapSet.member?(state.live_per_room[room.id] || MapSet.new(), 1)
      assert Map.has_key?(state.pending_join, room.id)

      # Wait past join grace.
      Process.sleep(join_grace() + 50)

      assert {:ok, _pid} = Registry.lookup(room.id)
      :ok = Supervisor.terminate(room.id)
    end

    test "a second arrival in the same room is idempotent (no second scheduler)" do
      room = insert_room()

      Lifecycle.notify(synth_arrived(room.id, 1))
      Lifecycle.notify(synth_arrived(room.id, 2))
      _ = Lifecycle.get_state()

      Process.sleep(join_grace() + 50)

      assert {:ok, _pid} = Registry.lookup(room.id)
      :ok = Supervisor.terminate(room.id)
    end
  end

  describe "≥1 → 0 transition" do
    test "RoomPlayerLeft on the last occupant schedules a leave-grace timer" do
      room = insert_room()

      Lifecycle.notify(synth_arrived(room.id, 1))
      Process.sleep(join_grace() + 50)
      assert {:ok, _pid} = Registry.lookup(room.id)

      Lifecycle.notify(synth_left(room.id, 1))
      _ = Lifecycle.get_state()

      state = Lifecycle.get_state()
      assert Map.has_key?(state.pending_leave, room.id)

      Process.sleep(leave_grace() + 50)
      assert :error = Registry.lookup(room.id)
    end

    test "re-entry within leave grace cancels the teardown" do
      room = insert_room()

      Lifecycle.notify(synth_arrived(room.id, 1))
      Process.sleep(join_grace() + 30)

      Lifecycle.notify(synth_left(room.id, 1))
      # Re-enter immediately, well within leave_grace_ms.
      Lifecycle.notify(synth_arrived(room.id, 2))
      _ = Lifecycle.get_state()

      Process.sleep(leave_grace() + 50)
      assert {:ok, _pid} = Registry.lookup(room.id)

      :ok = Supervisor.terminate(room.id)
    end

    test "re-entry AFTER leave grace gets a fresh scheduler" do
      room = insert_room()

      Lifecycle.notify(synth_arrived(room.id, 1))
      Process.sleep(join_grace() + 30)
      Lifecycle.notify(synth_left(room.id, 1))
      Process.sleep(leave_grace() + 50)

      assert :error = Registry.lookup(room.id)

      Lifecycle.notify(synth_arrived(room.id, 2))
      Process.sleep(join_grace() + 50)
      assert {:ok, _pid} = Registry.lookup(room.id)

      :ok = Supervisor.terminate(room.id)
    end
  end
end
