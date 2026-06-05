defmodule AgenticRealms.World.Commands.EditNpcTest do
  @moduledoc """
  Feature 015 US7 — editing NPC blueprints + in-world NPC clones.

  * Blueprint edit is revision-tracked + optimistically locked (a concurrent
    stale edit is refused) and does NOT retro-propagate to already-spawned
    clones (FR-009/FR-017).
  * In-place clone edit (`edit_npc/3`) changes only that clone.
  """

  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Queries}
  alias AgenticRealms.World.Schemas.{NPCClone, Region, Room}

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wiz_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    region_id = Ecto.UUID.generate()
    room_id = Ecto.UUID.generate()
    Repo.insert!(%Region{id: region_id, name: "R#{suffix}", inserted_at: now, updated_at: now})

    Repo.insert!(%Room{
      id: room_id,
      name: "Room #{suffix}",
      description: "x",
      behaviors: [],
      region_id: region_id,
      inserted_at: now,
      updated_at: now
    })

    # Wizard stands in the room so co-location passes for clone edits.
    {:ok, _} = Commands.spawn(wizard.id, room_id)

    slug = "troll_#{suffix}"

    {:ok, ^slug} =
      Commands.create_npc_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: slug,
        name: "Troll #{suffix}",
        short_description: "a troll",
        long_description: "A troll.",
        lore: "original lore"
      })

    %{wizard: wizard, room_id: room_id, slug: slug, suffix: suffix}
  end

  test "blueprint edit bumps revision; a concurrent stale edit is refused",
       %{wizard: wizard, slug: slug} do
    assert {:ok, 2} =
             Commands.edit_object_blueprint(wizard.id, slug, %{
               expected_revision: 1,
               fields_changed: %{lore: "v2 lore"}
             })

    # A second editor still on revision 1 is refused with the current revision.
    assert {:error, :stale_revision, current_revision: 2} =
             Commands.edit_object_blueprint(wizard.id, slug, %{
               expected_revision: 1,
               fields_changed: %{lore: "v3 lore"}
             })

    assert Queries.get_npc_blueprint_row(slug).lore == "v2 lore"
  end

  test "editing the blueprint does not retro-propagate to a spawned clone (FR-017)",
       %{wizard: wizard, room_id: room_id, slug: slug} do
    {:ok, clone_id} = Commands.spawn_from_blueprint(wizard.id, slug, room_id)
    assert Repo.get(NPCClone, clone_id).lore == "original lore"

    {:ok, 2} =
      Commands.edit_object_blueprint(wizard.id, slug, %{
        expected_revision: 1,
        fields_changed: %{lore: "edited blueprint lore"}
      })

    # The frozen clone is untouched.
    assert Repo.get(NPCClone, clone_id).lore == "original lore"
  end

  test "in-place clone edit changes only that clone",
       %{wizard: wizard, room_id: room_id, slug: slug} do
    {:ok, clone_a} = Commands.spawn_from_blueprint(wizard.id, slug, room_id)

    # Rename the blueprint so the sibling clone gets a distinct name (the
    # per-room name-collision guard would otherwise reject a second clone).
    {:ok, 2} =
      Commands.edit_object_blueprint(wizard.id, slug, %{
        expected_revision: 1,
        fields_changed: %{name: "Sibling Troll"}
      })

    {:ok, clone_b} = Commands.spawn_from_blueprint(wizard.id, slug, room_id)

    assert {:ok, :updated} =
             Commands.edit_npc(wizard.id, clone_a, %{long_description: "Now scarred and grim."})

    assert Repo.get(NPCClone, clone_a).long_description == "Now scarred and grim."
    # The sibling clone is unaffected.
    refute Repo.get(NPCClone, clone_b).long_description == "Now scarred and grim."
  end

  test "in-place clone edit refuses when the wizard isn't co-located",
       %{wizard: wizard, room_id: room_id, slug: slug, suffix: suffix} do
    {:ok, clone_id} = Commands.spawn_from_blueprint(wizard.id, slug, room_id)

    # A different wizard who is NOT in the clone's room.
    {:ok, other} =
      Accounts.register_player(%{username: "other_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(other.id)

    assert {:error, :object_not_editable_here} =
             Commands.edit_npc(other.id, clone_id, %{lore: "hijack"})
  end
end
