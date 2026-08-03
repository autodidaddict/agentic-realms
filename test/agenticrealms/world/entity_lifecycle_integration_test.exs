defmodule AgenticRealms.World.EntityLifecycleIntegrationTest do
  @moduledoc """
  End-to-end entity lifecycle: relocation between
  containers, the void state, and container-type uniformity.
  Asserts read-model container transitions through the live clone/move service.
  """

  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  import Ecto.Query

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, ContainerRef, Seed}
  alias AgenticRealms.World.Schemas.{Object, Room}

  setup do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])

    {:ok, wiz} = Accounts.register_player(%{username: "elc_#{suffix}", password: "pw12345678"})
    {:ok, _} = Accounts.promote_to_wizard(wiz.id)

    room_ids = Repo.all(from(r in Room, select: r.id, limit: 3))
    [room_a, room_b | _] = room_ids

    fields = %{
      name: "lifecycle pot #{suffix}",
      short_description: "a lifecycle pot",
      long_description: "A pot exercised through the entity lifecycle.",
      fixed: false,
      behaviors: [],
      quest_player_id: nil,
      quest_instance_id: nil
    }

    %{wiz: wiz, room_a: room_a, room_b: room_b, fields: fields}
  end

  defp container(id), do: Repo.get(Object, id) |> then(&{&1.container_type, &1.container_id})

  describe "US4 — the void" do
    test "a cloned-but-unplaced entity exists in the void and is in no room", %{
      fields: fields,
      room_a: room
    } do
      {:ok, oid} = Commands.clone_entity(:object, fields)

      assert {"void", nil} = container(oid)
      refute oid in Enum.map(AgenticRealms.World.Queries.list_objects_in_room(room), & &1.id)

      assert :ok =
               Commands.move_entity(oid, ContainerRef.void(), ContainerRef.room(room), :relocated)

      assert {"room", ^room} = container(oid)
    end

    test "moving an entity into the void removes it from its room", %{
      fields: fields,
      room_a: room
    } do
      {:ok, oid} = Commands.clone_into(:object, fields, ContainerRef.room(room), :spawned)
      assert {"room", ^room} = container(oid)

      assert :ok =
               Commands.move_entity(oid, ContainerRef.room(room), ContainerRef.void(), :relocated)

      assert {"void", nil} = container(oid)
      refute oid in Enum.map(AgenticRealms.World.Queries.list_objects_in_room(room), & &1.id)
    end
  end

  describe "US3 — relocation between rooms" do
    test "an entity moves from room A to room B, ending in exactly one container",
         %{fields: fields, room_a: a, room_b: b} do
      {:ok, oid} = Commands.clone_into(:object, fields, ContainerRef.room(a), :spawned)
      assert {"room", ^a} = container(oid)

      assert :ok =
               Commands.move_entity(oid, ContainerRef.room(a), ContainerRef.room(b), :relocated)

      assert {"room", ^b} = container(oid)
      ids_a = Enum.map(AgenticRealms.World.Queries.list_objects_in_room(a), & &1.id)
      ids_b = Enum.map(AgenticRealms.World.Queries.list_objects_in_room(b), & &1.id)
      refute oid in ids_a
      assert oid in ids_b
    end

    test "a stale-origin relocation is refused", %{fields: fields, room_a: a, room_b: b} do
      {:ok, oid} = Commands.clone_into(:object, fields, ContainerRef.room(a), :spawned)

      assert {:error, :container_conflict} =
               Commands.move_entity(oid, ContainerRef.room(b), ContainerRef.void(), :relocated)

      assert {"room", ^a} = container(oid)
    end
  end

  describe "US5 — container-type uniformity" do
    test "the same move operation routes an object to a room and to a player inventory",
         %{fields: fields, room_a: room, wiz: wiz} do
      {:ok, oid} = Commands.clone_into(:object, fields, ContainerRef.room(room), :spawned)
      assert {"room", ^room} = container(oid)

      assert :ok =
               Commands.move_entity(
                 oid,
                 ContainerRef.room(room),
                 ContainerRef.player(wiz.id),
                 :taken
               )

      assert {"player", pid_str} = container(oid)
      assert pid_str == Integer.to_string(wiz.id)
    end

    test "the NPC-inventory container type is accepted by the model (defined-but-dormant)",
         %{fields: fields, room_a: room} do
      {:ok, oid} = Commands.clone_into(:object, fields, ContainerRef.room(room), :spawned)

      assert :ok =
               Commands.move_entity(
                 oid,
                 ContainerRef.room(room),
                 ContainerRef.npc("some-npc-id"),
                 :relocated
               )

      assert {"npc", "some-npc-id"} = container(oid)
    end
  end
end
