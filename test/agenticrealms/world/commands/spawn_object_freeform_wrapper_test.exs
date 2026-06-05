defmodule AgenticRealms.World.Commands.SpawnObjectFreeformWrapperTest do
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Queries, Seed}
  alias AgenticRealms.World.Schemas.{Object, ObjectBlueprint}

  setup do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wff_#{suffix}", password: "pw12345678"})

    {:ok, non_wizard} =
      Accounts.register_player(%{username: "nwff_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())
    {:ok, _} = Commands.spawn(non_wizard.id, Seed.starting_room_id())

    %{
      wizard: wizard,
      non_wizard: non_wizard,
      starting_room_id: Seed.starting_room_id(),
      suffix: suffix
    }
  end

  test "spawns a freeform Object with no Blueprint row added",
       %{wizard: w, starting_room_id: room_id, suffix: suffix} do
    blueprint_count_before = length(Queries.list_object_blueprints())

    assert {:ok, object_id} =
             Commands.spawn_object_freeform(w.id, room_id, %{
               name: "freeform pot #{suffix}",
               short_description: "a small clay pot",
               long_description: "A small clay pot, half-empty of dry barley."
             })

    assert %Object{container_type: "room", container_id: ^room_id, name: name} =
             Repo.get(Object, object_id)

    assert name == "freeform pot #{suffix}"

    # FR-011: no blueprint row added.
    blueprint_count_after = length(Queries.list_object_blueprints())
    assert blueprint_count_after == blueprint_count_before

    # Defense in depth — the schema has no blueprint_id column.
    refute Map.has_key?(Map.from_struct(Repo.get(Object, object_id)), :blueprint_id)
  end

  test "refuses non-wizard caller", %{non_wizard: nw, starting_room_id: room_id} do
    assert {:error, :not_a_wizard} =
             Commands.spawn_object_freeform(nw.id, room_id, %{
               name: "x",
               short_description: "y",
               long_description: "z"
             })
  end

  test "refuses missing required content fields", %{wizard: w, starting_room_id: room_id} do
    assert {:error, :name_required} =
             Commands.spawn_object_freeform(w.id, room_id, %{
               name: "",
               short_description: "y",
               long_description: "z"
             })

    assert {:error, :short_description_required} =
             Commands.spawn_object_freeform(w.id, room_id, %{
               name: "x",
               short_description: nil,
               long_description: "z"
             })

    assert {:error, :long_description_required} =
             Commands.spawn_object_freeform(w.id, room_id, %{
               name: "x",
               short_description: "y",
               long_description: "  "
             })
  end

  test "two freeform spawns produce two distinct objects in the same room",
       %{wizard: w, starting_room_id: room_id, suffix: suffix} do
    attrs = %{
      name: "freeform dup #{suffix}",
      short_description: "a small clay pot",
      long_description: "A small clay pot."
    }

    {:ok, id_a} = Commands.spawn_object_freeform(w.id, room_id, attrs)
    {:ok, id_b} = Commands.spawn_object_freeform(w.id, room_id, attrs)

    assert id_a != id_b
    assert Repo.get(Object, id_a).container_id == room_id
    assert Repo.get(Object, id_b).container_id == room_id
  end

  test "freeform Object is observationally indistinguishable from a blueprint-spawned one (FR-012)",
       %{wizard: w, starting_room_id: room_id, suffix: suffix} do
    slug = "comparison_pot_#{suffix}"

    {:ok, ^slug} =
      Commands.create_object_blueprint(%{
        wizard_id: w.id,
        blueprint_id: slug,
        name: "comparison pot",
        short_description: "a small clay pot",
        long_description: "A small clay pot."
      })

    {:ok, from_bp} = Commands.spawn_object_from_blueprint(w.id, slug, room_id)

    {:ok, freeform} =
      Commands.spawn_object_freeform(w.id, room_id, %{
        name: "comparison pot",
        short_description: "a small clay pot",
        long_description: "A small clay pot."
      })

    a = Repo.get(Object, from_bp)
    b = Repo.get(Object, freeform)

    # Same content fields; same room; same schema shape; both lack
    # blueprint_id columns.
    assert a.name == b.name
    assert a.short_description == b.short_description
    assert a.long_description == b.long_description
    assert a.fixed == b.fixed
    assert a.container_type == b.container_type
    assert a.container_id == b.container_id
    assert Map.keys(Map.from_struct(a)) == Map.keys(Map.from_struct(b))
    refute Map.has_key?(Map.from_struct(a), :blueprint_id)

    # Blueprint registry contains exactly one row for this scenario — the
    # one authored explicitly; the freeform path added none.
    assert %ObjectBlueprint{id: ^slug} = Repo.get(ObjectBlueprint, slug)
  end
end
