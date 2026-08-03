defmodule AgenticRealms.World.Commands.ConcurrentTakeTest do
  @moduledoc """
  The concurrent-"already taken"
  regression test that replaces the old `Room`-aggregate `object_ids` guard.

  Two players resolve the same object in the room; the first take wins, and
  the second taker — acting on its already-resolved (now stale) view of the
  object being in the room — is refused with `:container_conflict`. The
  object stays with the first taker and is never stolen.
  """

  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, ContainerRef, Seed}
  alias AgenticRealms.World.Schemas.Object

  setup do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])
    room = Seed.starting_room_id()

    {:ok, wiz} = Accounts.register_player(%{username: "ctwiz_#{suffix}", password: "pw12345678"})
    {:ok, _} = Accounts.promote_to_wizard(wiz.id)
    {:ok, _} = Commands.spawn(wiz.id, room)

    name = "race pot #{suffix}"

    {:ok, object_id} =
      Commands.spawn_object_freeform(wiz.id, room, %{
        name: name,
        short_description: "a contested pot",
        long_description: "A pot two players grab at the same moment."
      })

    {:ok, alice} =
      Accounts.register_player(%{username: "alice_#{suffix}", password: "pw12345678"})

    {:ok, bob} = Accounts.register_player(%{username: "bob_#{suffix}", password: "pw12345678"})
    {:ok, _} = Commands.spawn(alice.id, room)
    {:ok, _} = Commands.spawn(bob.id, room)

    %{room: room, object_id: object_id, name: name, alice: alice, bob: bob}
  end

  test "second concurrent taker is refused and the object is not stolen",
       %{room: room, object_id: oid, name: name, alice: a, bob: b} do
    assert {:ok, %{object_id: ^oid}} = Commands.take(a.id, name)

    assert {:error, :container_conflict} =
             Commands.move_entity(oid, ContainerRef.room(room), ContainerRef.player(b.id), :taken)

    obj = Repo.get(Object, oid)
    assert obj.container_type == "player"
    assert obj.container_id == Integer.to_string(a.id)
    refute obj.container_id == Integer.to_string(b.id)
  end

  test "once Alice has it, Bob's take wrapper finds nothing in the room",
       %{object_id: oid, name: name, alice: a, bob: b} do
    assert {:ok, %{object_id: ^oid}} = Commands.take(a.id, name)

    assert {:error, :no_such_object} = Commands.take(b.id, name)

    assert Repo.get(Object, oid).container_id == Integer.to_string(a.id)
  end
end
