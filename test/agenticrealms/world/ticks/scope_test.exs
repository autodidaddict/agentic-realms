defmodule AgenticRealms.World.Ticks.ScopeTest do
  @moduledoc """
  Tests for the tick-behavior scope computation.
  """

  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.World.Schemas.{Blueprint, NPCClone, Object, PlayerState, Room}
  alias AgenticRealms.World.Ticks.Scope

  defp tick(text, interval_ms) do
    %{
      "trigger" => "tick",
      "interval_ms" => interval_ms,
      "actions" => [%{"type" => "say", "text" => text}]
    }
  end

  defp non_tick(text) do
    %{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => text}]}
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
      id: "test_bp_#{System.unique_integer([:positive])}",
      name: "BP",
      short_description: "s",
      long_description: "l"
    })
  end

  defp insert_clone(bp, room, opts \\ []) do
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

  defp insert_object_in_room(room, behaviors \\ []) do
    Repo.insert!(%Object{
      id: Ecto.UUID.generate(),
      name: "lantern",
      short_description: "a brass lantern",
      long_description: "A flickering brass lantern.",
      fixed: false,
      container_type: "room",
      container_id: room.id,
      behaviors: behaviors
    })
  end

  defp register_player(label) do
    suffix = System.unique_integer([:positive])

    {:ok, p} =
      AgenticRealms.Accounts.register_player(%{
        username: "#{label}_#{suffix}",
        password: "pw12345678"
      })

    p
  end

  defp put_in_room(player, room) do
    Repo.insert!(%PlayerState{player_id: player.id, current_room_id: room.id})
  end

  defp insert_object_carried_by(player, behaviors \\ []) do
    Repo.insert!(%Object{
      id: Ecto.UUID.generate(),
      name: "satchel",
      short_description: "a small satchel",
      long_description: "A small leather satchel.",
      fixed: false,
      container_type: "player",
      container_id: Integer.to_string(player.id),
      behaviors: behaviors
    })
  end

  describe "compute/1" do
    test "returns [] for an empty room with no behaviors" do
      room = insert_room()
      assert Scope.compute(room.id) == []
    end

    test "returns only tick-triggered behaviors" do
      room = insert_room([tick("a", 1000), non_tick("not tick")])
      entries = Scope.compute(room.id)
      assert length(entries) == 1
      assert [%{target_kind: :room, actions: [%{"text" => "a"}]}] = entries
    end

    test "includes NPC tick behaviors" do
      room = insert_room()
      bp = insert_blueprint()
      _clone = insert_clone(bp, room, behaviors: [tick("npc-tick", 1000)])

      entries = Scope.compute(room.id)
      assert Enum.any?(entries, &(&1.target_kind == :npc))
    end

    test "excludes NPCs in a different room" do
      room_a = insert_room()
      room_b = insert_room()
      bp = insert_blueprint()
      _clone_in_b = insert_clone(bp, room_b, behaviors: [tick("b-tick", 1000)])

      assert Scope.compute(room_a.id) == []
    end

    test "includes in-room object tick behaviors" do
      room = insert_room()
      _obj = insert_object_in_room(room, [tick("obj-tick", 1000)])

      entries = Scope.compute(room.id)
      assert Enum.any?(entries, &(&1.target_kind == :object))
    end

    test "includes carried-object tick behaviors when carrier is in room" do
      room = insert_room()
      player = register_player("alice")
      put_in_room(player, room)
      _obj = insert_object_carried_by(player, [tick("carried-tick", 1000)])

      entries = Scope.compute(room.id)
      assert Enum.any?(entries, &(&1.target_kind == :object))
    end

    test "excludes carried-object behaviors when carrier is in a different room" do
      room_a = insert_room()
      room_b = insert_room()
      player = register_player("bob")
      put_in_room(player, room_b)
      _obj = insert_object_carried_by(player, [tick("carried-tick", 1000)])

      assert Scope.compute(room_a.id) == []
    end

    test "sorts entries: room → NPC → object; within a target by behavior_index" do
      room =
        insert_room([
          tick("room-first", 1000),
          tick("room-second", 1000)
        ])

      bp = insert_blueprint()

      _clone1 = insert_clone(bp, room, name: "First NPC", behaviors: [tick("npc1", 1000)])
      _clone2 = insert_clone(bp, room, name: "Second NPC", behaviors: [tick("npc2", 1000)])

      _obj = insert_object_in_room(room, [tick("obj", 1000)])

      entries = Scope.compute(room.id)

      kinds_and_texts =
        Enum.map(entries, fn e ->
          {e.target_kind, hd(e.actions)["text"]}
        end)

      assert Enum.take(kinds_and_texts, 2) == [{:room, "room-first"}, {:room, "room-second"}]
      assert List.last(kinds_and_texts) == {:object, "obj"}
      npc_texts = for {:npc, t} <- kinds_and_texts, do: t
      assert Enum.sort(npc_texts) == ["npc1", "npc2"]
    end
  end

  describe "incremental helpers" do
    test "add_npc/2 + remove_npc/2 round-trip" do
      room = insert_room()
      bp = insert_blueprint()
      clone = insert_clone(bp, room, behaviors: [tick("hi", 1000)])

      base = Scope.compute(room.id)
      added = Scope.add_npc(base, clone.id)
      assert length(added) == length(base)

      removed = Scope.remove_npc(base, clone.id)
      refute Enum.any?(removed, &(&1.target_kind == :npc))
    end

    test "remove_carried_object/3 filters by object_id" do
      room = insert_room()
      player = register_player("eve")
      put_in_room(player, room)
      obj = insert_object_carried_by(player, [tick("c", 1000)])

      base = Scope.compute(room.id)
      assert Enum.any?(base, &(&1.target_kind == :object and &1.target_id == obj.id))

      removed = Scope.remove_carried_object(base, player.id, obj.id)
      refute Enum.any?(removed, &(&1.target_kind == :object and &1.target_id == obj.id))
    end
  end
end
