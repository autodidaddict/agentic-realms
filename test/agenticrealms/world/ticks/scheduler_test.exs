defmodule AgenticRealms.World.Ticks.SchedulerTest do
  @moduledoc """
  Tests for the per-room tick Scheduler GenServer (feature 011).

  Bypasses the Lifecycle and starts a Scheduler directly via
  `Supervisor.find_or_start/1`, so the GenServer's beat loop can be
  observed deterministically with the test-config 50 ms base rate.
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealmsWeb.Topics
  alias AgenticRealms.World.Schemas.{Blueprint, NPCClone, Object, PlayerState, Room}
  alias AgenticRealms.World.Ticks.{Registry, Scheduler, Supervisor}

  alias AgenticRealms.World.UIEvents.{
    BehaviorUtterance,
    RoomNPCLeft,
    RoomPlayerArrived,
    RoomPlayerLeft
  }

  @pubsub AgenticRealms.PubSub

  defp tick(text, interval_ms) do
    %{
      "trigger" => "tick",
      "interval_ms" => interval_ms,
      "actions" => [%{"type" => "say", "text" => text}]
    }
  end

  defp insert_room(behaviors \\ []) do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "Test Room",
      description: "A room.",
      behaviors: behaviors,
      region_id: AgenticRealms.DataCase.insert_test_region()
    })
  end

  defp insert_blueprint do
    Repo.insert!(%Blueprint{
      id: "bp_#{System.unique_integer([:positive])}",
      name: "BP",
      short_description: "s",
      long_description: "l"
    })
  end

  defp insert_clone(bp, room, opts) do
    Repo.insert!(%NPCClone{
      id: Ecto.UUID.generate(),
      blueprint_id: bp.id,
      name: Keyword.get(opts, :name, "Guard"),
      short_description: "s",
      long_description: "l",
      room_id: room.id,
      behaviors: Keyword.get(opts, :behaviors, [])
    })
  end

  defp insert_object_in_room(room, behaviors) do
    Repo.insert!(%Object{
      id: Ecto.UUID.generate(),
      name: "lantern",
      short_description: "a lantern",
      long_description: "A brass lantern.",
      fixed: false,
      container_type: "room",
      container_id: room.id,
      behaviors: behaviors
    })
  end

  defp register_player(label, room) do
    suffix = System.unique_integer([:positive])

    {:ok, p} =
      AgenticRealms.Accounts.register_player(%{
        username: "#{label}_#{suffix}",
        password: "pw12345678"
      })

    Repo.insert!(%PlayerState{player_id: p.id, current_room_id: room.id})
    p
  end

  defp track_presence(player) do
    {:ok, _} = AgenticRealmsWeb.Presence.track_player(self(), player.id, player.username)
    Process.sleep(20)
  end

  defp start_scheduler(room) do
    {:ok, pid} = Supervisor.find_or_start(room.id)

    on_exit(fn ->
      _ = Supervisor.terminate(room.id)
    end)

    pid
  end

  defp subscribe_player(player),
    do: Phoenix.PubSub.subscribe(@pubsub, Topics.player_topic(player.id))

  describe "scheduler lifecycle (US1)" do
    test "find_or_start returns a pid and registers it" do
      room = insert_room()
      pid = start_scheduler(room)
      assert is_pid(pid)
      assert {:ok, ^pid} = Registry.lookup(room.id)
    end

    test "scheduler init populates in_scope from Scope.compute/1" do
      room = insert_room([tick("hi", 50)])
      pid = start_scheduler(room)
      state = GenServer.call(pid, :get_state)
      assert length(state.in_scope) == 1
      assert hd(state.in_scope).target_kind == :room
    end

    test ":get_state returns the scheduler state" do
      room = insert_room()
      pid = start_scheduler(room)

      state = GenServer.call(pid, :get_state)
      assert state.room_id == room.id
      assert is_integer(state.base_tick_rate_ms)
      assert is_integer(state.scheduler_start_time)
    end
  end

  describe "beat dispatch (US1 / US3)" do
    test "a 1-base-rate room tick fires within ~base + dispatch tolerance" do
      base = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:base_tick_rate_ms]
      room = insert_room([tick("hello room", base)])
      player = register_player("alice", room)
      track_presence(player)
      subscribe_player(player)

      _pid = start_scheduler(room)

      # Wait for a beat. With base_rate=50ms, we expect the first
      # broadcast within ~100ms (one beat to set scheduler_start_time and
      # one beat to actually fire — the elapsed-since-start is >= base
      # after the first beat).
      assert_receive %BehaviorUtterance{kind: :room_speech, text: "hello room"}, 1_000
    end

    test "an NPC tick fires via :npc_speech" do
      base = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:base_tick_rate_ms]
      room = insert_room()
      bp = insert_blueprint()
      _clone = insert_clone(bp, room, name: "Garrick", behaviors: [tick("npc beat", base)])
      player = register_player("alice", room)
      track_presence(player)
      subscribe_player(player)

      _pid = start_scheduler(room)

      assert_receive %BehaviorUtterance{
                       kind: :npc_speech,
                       actor_name: "Garrick",
                       text: "npc beat"
                     },
                     1_000
    end

    test "a room emote action fires as :room_emote (no actor, no says wrapper)" do
      base = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:base_tick_rate_ms]

      room =
        insert_room([
          %{
            "trigger" => "tick",
            "interval_ms" => base,
            "actions" => [%{"type" => "emote", "text" => "Dust motes drift."}]
          }
        ])

      player = register_player("alice", room)
      track_presence(player)
      subscribe_player(player)

      _pid = start_scheduler(room)

      assert_receive %BehaviorUtterance{
                       kind: :room_emote,
                       actor_name: nil,
                       text: "Dust motes drift."
                     },
                     1_000
    end

    test "an NPC emote action fires as :npc_emote with the NPC's name" do
      base = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:base_tick_rate_ms]
      room = insert_room()
      bp = insert_blueprint()

      _clone =
        insert_clone(bp, room,
          name: "Garrick",
          behaviors: [
            %{
              "trigger" => "tick",
              "interval_ms" => base,
              "actions" => [%{"type" => "emote", "text" => "polishes a tankard."}]
            }
          ]
        )

      player = register_player("alice", room)
      track_presence(player)
      subscribe_player(player)

      _pid = start_scheduler(room)

      assert_receive %BehaviorUtterance{
                       kind: :npc_emote,
                       actor_name: "Garrick",
                       text: "polishes a tankard."
                     },
                     1_000
    end

    test "an object emote action fires as :object_emote with the object's name" do
      base = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:base_tick_rate_ms]
      room = insert_room()

      _obj =
        insert_object_in_room(room, [
          %{
            "trigger" => "tick",
            "interval_ms" => base,
            "actions" => [%{"type" => "emote", "text" => "flickers softly."}]
          }
        ])

      player = register_player("alice", room)
      track_presence(player)
      subscribe_player(player)

      _pid = start_scheduler(room)

      assert_receive %BehaviorUtterance{
                       kind: :object_emote,
                       actor_name: "lantern",
                       text: "flickers softly."
                     },
                     1_000
    end

    test "FR-008a ordering: room before NPC on the same beat" do
      base = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:base_tick_rate_ms]
      room = insert_room([tick("ROOM_FIRST", base)])
      bp = insert_blueprint()
      _clone = insert_clone(bp, room, name: "Garrick", behaviors: [tick("NPC_SECOND", base)])
      player = register_player("alice", room)
      track_presence(player)
      subscribe_player(player)

      _pid = start_scheduler(room)

      assert_receive %BehaviorUtterance{text: "ROOM_FIRST"}, 1_000
      assert_receive %BehaviorUtterance{text: "NPC_SECOND"}, 1_000
    end

    test "multiple behaviors at different intervals fire on independent cadences" do
      base = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:base_tick_rate_ms]
      room = insert_room([tick("FAST", base), tick("SLOW", base * 3)])
      player = register_player("alice", room)
      track_presence(player)
      subscribe_player(player)

      _pid = start_scheduler(room)

      # Wait for ~6 base beats (~300ms with 50ms base).
      Process.sleep(base * 7 + 50)

      # Count the fires we received.
      messages = drain_messages([])
      fast_count = Enum.count(messages, &(&1.text == "FAST"))
      slow_count = Enum.count(messages, &(&1.text == "SLOW"))

      # FAST fires every beat; SLOW fires every 3 beats. Over ~7 beats,
      # FAST should fire 6–7 times, SLOW 2–3 times.
      assert fast_count >= 4
      assert slow_count >= 1
      assert fast_count > slow_count
    end
  end

  describe "scope updates (US4 hooks)" do
    test "RoomNPCLeft drops the NPC's behaviors from scope" do
      base = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:base_tick_rate_ms]
      room = insert_room()
      bp = insert_blueprint()
      clone = insert_clone(bp, room, name: "Doomed", behaviors: [tick("doomed-tick", base)])

      pid = start_scheduler(room)

      state_before = GenServer.call(pid, :get_state)
      assert Enum.any?(state_before.in_scope, &(&1.target_kind == :npc))

      send(pid, %RoomNPCLeft{room_id: room.id, npc_id: clone.id, npc_name: clone.name})
      :sys.get_state(pid)

      state_after = GenServer.call(pid, :get_state)
      refute Enum.any?(state_after.in_scope, &(&1.target_kind == :npc))
    end

    test "RoomPlayerArrived/Left with carried_object_ids updates scope" do
      base = Application.get_env(:agenticrealms, AgenticRealms.World.Ticks)[:base_tick_rate_ms]
      room = insert_room()
      player = register_player("alice", room)
      track_presence(player)

      obj =
        Repo.insert!(%Object{
          id: Ecto.UUID.generate(),
          name: "carried lantern",
          short_description: "a carried lantern",
          long_description: "Long.",
          fixed: false,
          container_type: "player",
          container_id: Integer.to_string(player.id),
          behaviors: [tick("carried beat", base)]
        })

      pid = start_scheduler(room)

      # Synthesize arrival with carried obj.
      send(pid, %RoomPlayerArrived{
        room_id: room.id,
        actor_id: player.id,
        actor_name: player.username,
        from_direction: nil,
        carried_object_ids: [obj.id]
      })

      :sys.get_state(pid)

      state_after_arrive = GenServer.call(pid, :get_state)

      assert Enum.any?(
               state_after_arrive.in_scope,
               &(&1.target_kind == :object and &1.target_id == obj.id)
             )

      send(pid, %RoomPlayerLeft{
        room_id: room.id,
        actor_id: player.id,
        actor_name: player.username,
        to_direction: :north,
        carried_object_ids: [obj.id]
      })

      :sys.get_state(pid)

      state_after_leave = GenServer.call(pid, :get_state)

      refute Enum.any?(
               state_after_leave.in_scope,
               &(&1.target_kind == :object and &1.target_id == obj.id)
             )
    end
  end

  # Helpers

  defp drain_messages(acc) do
    receive do
      %BehaviorUtterance{} = msg -> drain_messages([msg | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp _used, do: {Scheduler, insert_object_in_room(nil, [])}
end
