defmodule AgenticRealms.World.Commands.SpawnNpcFreeformTest do
  @moduledoc """
  A freeform one-off NPC is cloned straight into a room with
  no blueprint behind it: a real `npc_clones` row (null `blueprint_id`) carrying
  the authored lore, observationally identical to a blueprint-spawned clone, and
  NO `blueprints` row added.
  """

  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  import Ecto.Query

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Commands
  alias AgenticRealms.World.Schemas.{Blueprint, NPCClone, Region, Room}

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wiz_#{suffix}", password: "pw12345678"})

    {:ok, non_wizard} =
      Accounts.register_player(%{username: "nw_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    region_id = Ecto.UUID.generate()
    room_id = Ecto.UUID.generate()

    Repo.insert!(%Region{id: region_id, name: "R#{suffix}", inserted_at: now, updated_at: now})

    Repo.insert!(%Room{
      id: room_id,
      name: "Room #{suffix}",
      description: "An empty test room.",
      behaviors: [],
      region_id: region_id,
      inserted_at: now,
      updated_at: now
    })

    %{wizard: wizard, non_wizard: non_wizard, room_id: room_id, suffix: suffix}
  end

  test "spawns a blueprint-less clone carrying lore, no blueprints row added",
       %{wizard: wizard, room_id: room_id, suffix: suffix} do
    blueprints_before = Repo.aggregate(Blueprint, :count)

    assert {:ok, _entity_id} =
             Commands.spawn_npc_freeform(wizard.id, room_id, %{
               name: "courier #{suffix}",
               short_description: "a nervous courier",
               long_description: "A wiry courier catching his breath by the door.",
               lore: "Carries a sealed letter he must not lose."
             })

    clone = Repo.get_by(NPCClone, name: "courier #{suffix}")
    refute is_nil(clone)
    assert is_nil(clone.blueprint_id)
    assert clone.room_id == room_id
    assert clone.lore == "Carries a sealed letter he must not lose."

    assert Repo.aggregate(Blueprint, :count) == blueprints_before
    assert [] = Repo.all(from(b in Blueprint, where: b.name == ^"courier #{suffix}"))
  end

  test "refuses a non-wizard caller", %{non_wizard: nw, room_id: room_id} do
    assert {:error, :not_a_wizard} =
             Commands.spawn_npc_freeform(nw.id, room_id, %{
               name: "x",
               short_description: "y",
               long_description: "z"
             })
  end

  test "refuses a per-room name collision",
       %{wizard: wizard, room_id: room_id, suffix: suffix} do
    name = "twin #{suffix}"

    {:ok, _} =
      Commands.spawn_npc_freeform(wizard.id, room_id, %{
        name: name,
        short_description: "the first",
        long_description: "The first of the pair."
      })

    assert {:error, :clone_name_taken_in_room} =
             Commands.spawn_npc_freeform(wizard.id, room_id, %{
               name: name,
               short_description: "the second",
               long_description: "The second of the pair."
             })
  end
end
