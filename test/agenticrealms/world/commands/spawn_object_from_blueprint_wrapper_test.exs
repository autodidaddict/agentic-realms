defmodule AgenticRealms.World.Commands.SpawnObjectFromBlueprintWrapperTest do
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Queries, Seed}
  alias AgenticRealms.World.Schemas.Object

  setup do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wiz_#{suffix}", password: "pw12345678"})

    {:ok, non_wizard} =
      Accounts.register_player(%{username: "nw_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())
    {:ok, _} = Commands.spawn(non_wizard.id, Seed.starting_room_id())

    slug = "test_chest_#{suffix}"

    {:ok, ^slug} =
      Commands.create_object_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: slug,
        name: "test chest",
        short_description: "a brass-bound test chest",
        long_description: "An exhaustively-tested chest carved with the seal of the unit test."
      })

    %{
      wizard: wizard,
      non_wizard: non_wizard,
      slug: slug,
      starting_room_id: Seed.starting_room_id()
    }
  end

  test "spawns an Object into the destination room with the blueprint's payload",
       %{wizard: w, slug: slug, starting_room_id: room_id} do
    assert {:ok, object_id} =
             Commands.spawn_object_from_blueprint(w.id, slug, room_id)

    assert %Object{
             id: ^object_id,
             room_id: ^room_id,
             name: "test chest",
             short_description: "a brass-bound test chest",
             fixed: false
           } = Repo.get(Object, object_id)

    # FR-013 — the world_objects schema must NOT have gained a
    # blueprint_id column as part of this milestone.
    refute Map.has_key?(Map.from_struct(Repo.get(Object, object_id)), :blueprint_id)
  end

  test "refuses non-wizard caller", %{non_wizard: nw, slug: slug, starting_room_id: room_id} do
    assert {:error, :not_a_wizard} =
             Commands.spawn_object_from_blueprint(nw.id, slug, room_id)
  end

  test "refuses unknown blueprint_id", %{wizard: w, starting_room_id: room_id} do
    assert {:error, :unknown_blueprint} =
             Commands.spawn_object_from_blueprint(w.id, "no_such_thing", room_id)
  end

  test "two spawns into the same room produce two distinct objects",
       %{wizard: w, slug: slug, starting_room_id: room_id} do
    {:ok, id_a} = Commands.spawn_object_from_blueprint(w.id, slug, room_id)
    {:ok, id_b} = Commands.spawn_object_from_blueprint(w.id, slug, room_id)

    assert id_a != id_b
    assert Repo.get(Object, id_a).room_id == room_id
    assert Repo.get(Object, id_b).room_id == room_id
  end

  test "spawned object reflects the blueprint's CURRENT denormalized payload",
       %{wizard: w, slug: slug, starting_room_id: room_id} do
    # Verify the wrapper actually stamps the blueprint payload (not the
    # call-site values). The blueprint was created in setup with
    # name "test chest" — that's what should appear on the row.
    {:ok, object_id} = Commands.spawn_object_from_blueprint(w.id, slug, room_id)
    obj = Queries.get_object_blueprint(slug)
    row = Repo.get(Object, object_id)

    assert row.name == obj.name
    assert row.short_description == obj.short_description
    assert row.long_description == obj.long_description
    assert row.fixed == obj.fixed
  end
end
