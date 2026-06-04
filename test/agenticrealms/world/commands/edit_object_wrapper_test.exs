defmodule AgenticRealms.World.Commands.EditObjectWrapperTest do
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Seed}
  alias AgenticRealms.World.Schemas.Object

  setup do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "weo_#{suffix}", password: "pw12345678"})

    {:ok, non_wizard} =
      Accounts.register_player(%{username: "neo_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())
    {:ok, _} = Commands.spawn(non_wizard.id, Seed.starting_room_id())

    {:ok, object_id} =
      Commands.spawn_object_freeform(wizard.id, Seed.starting_room_id(), %{
        name: "edit target #{suffix}",
        short_description: "a small edit-target",
        long_description: "A small edit-target Object."
      })

    %{
      wizard: wizard,
      non_wizard: non_wizard,
      object_id: object_id,
      suffix: suffix
    }
  end

  test "field-changing edit updates the row in place",
       %{wizard: w, object_id: oid} do
    assert {:ok, :updated} =
             Commands.edit_object(w.id, oid, %{
               short_description: "an edited-target"
             })

    row = Repo.get(Object, oid)
    assert row.short_description == "an edited-target"
  end

  test "no-op diff returns {:ok, :no_change} without dispatching",
       %{wizard: w, object_id: oid} do
    row_before = Repo.get(Object, oid)

    assert {:ok, :no_change} =
             Commands.edit_object(w.id, oid, %{name: row_before.name})

    row_after = Repo.get(Object, oid)
    assert row_after.updated_at == row_before.updated_at
  end

  test "non-wizard caller is refused", %{non_wizard: nw, object_id: oid} do
    assert {:error, :not_a_wizard} =
             Commands.edit_object(nw.id, oid, %{name: "x"})
  end

  test "unknown object is refused", %{wizard: w} do
    bogus_uuid = Ecto.UUID.generate()

    assert {:error, :unknown_object} =
             Commands.edit_object(w.id, bogus_uuid, %{name: "x"})
  end

  test "invalid field key is refused", %{wizard: w, object_id: oid} do
    assert {:error, :invalid_field} =
             Commands.edit_object(w.id, oid, %{behaviors: []})
  end

  test "edit on an object that's been picked up returns :object_not_editable_here",
       %{wizard: w, object_id: oid, suffix: suffix} do
    # Move the object into the wizard's inventory directly via Ecto
    # (bypassing the take flow for test brevity). Set room_id: nil to
    # simulate a carried object.
    {1, _} =
      Repo.update_all(
        from(o in Object, where: o.id == ^oid),
        set: [room_id: nil, player_id: w.id]
      )

    assert {:error, :object_not_editable_here} =
             Commands.edit_object(w.id, oid, %{name: "in_inventory_#{suffix}"})
  end

  import Ecto.Query
end
