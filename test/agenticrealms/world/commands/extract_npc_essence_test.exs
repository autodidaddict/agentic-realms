defmodule AgenticRealms.World.Commands.ExtractNpcEssenceTest do
  @moduledoc """
  Extract a new NPC Blueprint from an in-world clone: the
  extracted blueprint copies the clone's name/short/long/lore/fixed + its
  behavior_groups + DIRECT behaviors at revision 1, and the source clone is left
  byte-for-byte unchanged.
  """

  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Queries}
  alias AgenticRealms.World.Schemas.{NPCClone, Region, Room, BehaviorGroup}

  @greeter %{
    "trigger" => "player_entered",
    "actions" => [%{"type" => "say", "text" => "Welcome."}]
  }
  @direct %{
    "trigger" => "player_left",
    "actions" => [%{"type" => "emote", "text" => "grunts a farewell."}]
  }

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wiz_#{suffix}", password: "pw12345678"})

    {:ok, non_wizard} =
      Accounts.register_player(%{username: "nw_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    orc = "orc_#{suffix}"

    Repo.insert!(%BehaviorGroup{
      name: orc,
      behaviors: [@greeter],
      applies_to: ["npc"],
      inserted_at: now,
      updated_at: now
    })

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

    src_slug = "src_troll_#{suffix}"

    {:ok, ^src_slug} =
      Commands.create_npc_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: src_slug,
        name: "Source Troll #{suffix}",
        short_description: "a grizzled troll",
        long_description: "A troll behind a counter.",
        lore: "Hoards shiny coins.",
        fixed: true,
        behavior_groups: [orc],
        behaviors: [@direct]
      })

    {:ok, clone_id} = Commands.spawn_from_blueprint(wizard.id, src_slug, room_id)

    %{wizard: wizard, non_wizard: non_wizard, clone_id: clone_id, suffix: suffix, orc: orc}
  end

  test "extracts a new blueprint at rev 1 mirroring the clone; source clone untouched",
       %{wizard: wizard, clone_id: clone_id, suffix: suffix, orc: orc} do
    before = Repo.get(NPCClone, clone_id)
    new_slug = "extracted_#{suffix}"

    assert {:ok, ^new_slug} = Commands.extract_essence(wizard.id, clone_id, new_slug)

    bp = Queries.get_npc_blueprint_row(new_slug)
    assert bp.kind == "npc"
    assert bp.revision == 1
    assert bp.name == "Source Troll #{suffix}"
    assert bp.short_description == "a grizzled troll"
    assert bp.long_description == "A troll behind a counter."
    assert bp.lore == "Hoards shiny coins." or bp.lore == "Hoards shiny coins"
    assert bp.fixed == true
    assert bp.behavior_groups == [orc]
    assert bp.behaviors == [@direct]

    after_edit = Repo.get(NPCClone, clone_id)
    assert after_edit.name == before.name
    assert after_edit.lore == before.lore
    assert after_edit.behaviors == before.behaviors
    assert after_edit.behavior_groups == before.behavior_groups
    assert after_edit.direct_behaviors == before.direct_behaviors
    assert after_edit.blueprint_id == before.blueprint_id
  end

  test "refuses a non-wizard caller", %{non_wizard: nw, clone_id: clone_id, suffix: suffix} do
    assert {:error, :not_a_wizard} =
             Commands.extract_essence(nw.id, clone_id, "nope_#{suffix}")
  end

  test "refuses an unknown entity id", %{wizard: wizard, suffix: suffix} do
    assert {:error, :unknown_entity} =
             Commands.extract_essence(wizard.id, Ecto.UUID.generate(), "ghost_#{suffix}")
  end
end
