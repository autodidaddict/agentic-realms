defmodule AgenticRealms.World.Ticks.LifecycleTest do
  @moduledoc """
  Tests for the singleton tick Lifecycle GenServer.

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
      actor_name: "u",
      from_direction: nil,
      carried_object_ids: carried
    }
  end

  defp synth_left(room_id, player_id, carried \\ []) do
    %RoomPlayerLeft{
      room_id: room_id,
      actor_id: player_id,
      actor_name: "u",
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
      _ = Lifecycle.get_state()

      state = Lifecycle.get_state()
      assert MapSet.member?(state.live_per_room[room.id] || MapSet.new(), 1)
      assert Map.has_key?(state.pending_join, room.id)

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

  describe "rebuilding state on restart" do
    test "seeds live occupancy from the read model rather than starting empty" do
      room = insert_room()
      player = register_online_player_in(room.id)

      state = restart_lifecycle()

      assert MapSet.member?(state.live_per_room[room.id] || MapSet.new(), player.id)
    end

    test "seeds the started-scheduler set from the registry" do
      room = insert_room()
      register_online_player_in(room.id)
      {:ok, _pid} = Supervisor.find_or_start(room.id)

      state = restart_lifecycle()

      assert MapSet.member?(state.started_schedulers, room.id),
             "a scheduler that is already registered must be recognised after a restart"
    end

    test "an empty room whose scheduler survived the restart is reconciled away" do
      room = insert_room()
      {:ok, _pid} = Supervisor.find_or_start(room.id)
      assert {:ok, _} = Registry.lookup(room.id)

      restart_lifecycle()
      Process.sleep(leave_grace() * 3)
      _ = Lifecycle.get_state()

      assert Registry.lookup(room.id) == :error,
             "the orphaned scheduler should have been stopped by the restart reconcile"
    end

    defp register_online_player_in(room_id) do
      suffix = System.unique_integer([:positive])

      {:ok, player} =
        AgenticRealms.Accounts.register_player(%{
          username: "tick_#{suffix}",
          password: "pw12345678"
        })

      Repo.insert!(
        struct!(
          AgenticRealms.World.Schemas.PlayerState,
          [player_id: player.id, current_room_id: room_id] ++
            AgenticRealms.DataCase.character_columns()
        )
      )

      {:ok, _} = AgenticRealmsWeb.Presence.track_player(self(), player.id, player.username)
      Process.sleep(20)
      player
    end

    defp restart_lifecycle do
      old = Process.whereis(Lifecycle)
      ref = Process.monitor(old)
      Process.exit(old, :kill)
      assert_receive {:DOWN, ^ref, :process, ^old, :killed}, 2_000

      await_restart(old)
    end

    defp await_restart(old, attempts \\ 200) do
      case Process.whereis(Lifecycle) do
        pid when is_pid(pid) and pid != old ->
          Lifecycle.get_state()

        _ when attempts > 0 ->
          Process.sleep(10)
          await_restart(old, attempts - 1)

        _ ->
          flunk("Lifecycle did not restart")
      end
    end
  end
end
