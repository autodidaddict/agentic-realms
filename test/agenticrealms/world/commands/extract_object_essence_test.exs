defmodule AgenticRealms.World.Commands.ExtractObjectEssenceTest do
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
      Accounts.register_player(%{username: "wex_#{suffix}", password: "pw12345678"})

    {:ok, non_wizard} =
      Accounts.register_player(%{username: "nex_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())
    {:ok, _} = Commands.spawn(non_wizard.id, Seed.starting_room_id())

    {:ok, object_id} =
      Commands.spawn_object_freeform(wizard.id, Seed.starting_room_id(), %{
        name: "source pot",
        short_description: "a small clay pot",
        long_description: "A small clay pot, half-empty of dry barley."
      })

    %{
      wizard: wizard,
      non_wizard: non_wizard,
      object_id: object_id,
      suffix: suffix
    }
  end

  test "wholesale-copies the source object's fields into a new Blueprint at revision 1",
       %{wizard: w, object_id: oid, suffix: suffix} do
    slug = "extracted_pot_#{suffix}"

    assert {:ok, ^slug} = Commands.extract_essence(w.id, oid, slug)

    bp = Queries.get_object_blueprint(slug)

    assert bp.name == "source pot"
    assert bp.short_description == "a small clay pot"
    assert bp.long_description == "A small clay pot, half-empty of dry barley."
    assert bp.fixed == false
    assert bp.revision == 1
  end

  test "leaves the source Object unmodified",
       %{wizard: w, object_id: oid, suffix: suffix} do
    before = Repo.get(Object, oid)

    {:ok, _} = Commands.extract_essence(w.id, oid, "intact_check_#{suffix}")

    after_ = Repo.get(Object, oid)
    assert before.name == after_.name
    assert before.short_description == after_.short_description
    assert before.long_description == after_.long_description
    assert before.fixed == after_.fixed
    assert before.container_type == after_.container_type
    assert before.container_id == after_.container_id
  end

  test "refuses non-wizard caller",
       %{non_wizard: nw, object_id: oid, suffix: suffix} do
    assert {:error, :not_a_wizard} =
             Commands.extract_essence(nw.id, oid, "ban_#{suffix}")
  end

  test "refuses an unknown source entity",
       %{wizard: w, suffix: suffix} do
    bogus_uuid = Ecto.UUID.generate()

    assert {:error, :unknown_entity} =
             Commands.extract_essence(w.id, bogus_uuid, "unk_#{suffix}")
  end

  test "refuses invalid slug",
       %{wizard: w, object_id: oid} do
    assert {:error, :invalid_slug} =
             Commands.extract_essence(w.id, oid, "Has-Hyphens-And-Caps")
  end

  test "refuses slug collision with an existing Blueprint",
       %{wizard: w, object_id: oid, suffix: suffix} do
    slug = "collide_check_#{suffix}"

    {:ok, ^slug} = Commands.extract_essence(w.id, oid, slug)

    assert {:error, :slug_already_exists} =
             Commands.extract_essence(w.id, oid, slug)
  end
end
