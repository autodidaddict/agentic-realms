defmodule AgenticRealms.World.Commands.SpawnNpcComposeTest do
  @moduledoc """
  Feature 015 US4 — behavior_group composition is frozen onto the spawned clone:
  effective behaviors = union(behavior_groups, attachment order) ++ direct (FR-016),
  and editing a behavior_group after spawn does NOT mutate an existing clone (FR-017).
  """

  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  import Ecto.Query

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Commands
  alias AgenticRealms.World.Schemas.{NPCClone, Region, Room, BehaviorGroup}

  @orc_emote %{
    "trigger" => "player_entered",
    "actions" => [%{"type" => "emote", "text" => "grunts and hefts a club."}]
  }
  @shop_say %{
    "trigger" => "player_entered",
    "actions" => [%{"type" => "say", "text" => "Wares for sale."}]
  }
  @direct_bye %{
    "trigger" => "player_left",
    "actions" => [%{"type" => "say", "text" => "Hmph."}]
  }

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wiz_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    orc = "orc_#{suffix}"
    shop = "shop_#{suffix}"

    Repo.insert!(%BehaviorGroup{
      name: orc,
      behaviors: [@orc_emote],
      applies_to: ["npc"],
      inserted_at: now,
      updated_at: now
    })

    Repo.insert!(%BehaviorGroup{
      name: shop,
      behaviors: [@shop_say],
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
      description: "An empty test room.",
      behaviors: [],
      region_id: region_id,
      inserted_at: now,
      updated_at: now
    })

    %{wizard: wizard, suffix: suffix, room_id: room_id, orc: orc, shop: shop}
  end

  defp author_and_spawn(%{wizard: wizard, suffix: suffix, room_id: room_id, orc: orc, shop: shop}) do
    slug = "orc_shopkeeper_#{suffix}"

    {:ok, ^slug} =
      Commands.create_npc_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: slug,
        name: "Orc Shopkeeper #{suffix}",
        short_description: "a grizzled orc trader",
        long_description: "An orc behind a plank counter, eyeing your coin.",
        behavior_groups: [orc, shop],
        behaviors: [@direct_bye]
      })

    {:ok, _entity_id} = Commands.spawn_from_blueprint(wizard.id, slug, room_id)
    slug
  end

  test "effective behaviors = union(behavior_groups, order) ++ direct, nothing dropped (FR-016)",
       ctx do
    slug = author_and_spawn(ctx)
    clone = Repo.get_by(NPCClone, blueprint_id: slug)

    assert clone.behaviors == [@orc_emote, @shop_say, @direct_bye]
    assert clone.behavior_groups == [ctx.orc, ctx.shop]
    assert clone.direct_behaviors == [@direct_bye]
  end

  test "editing a behavior_group after spawn leaves the frozen clone unchanged (FR-017)",
       %{orc: orc} = ctx do
    slug = author_and_spawn(ctx)
    before = Repo.get_by(NPCClone, blueprint_id: slug)

    {1, _} =
      Repo.update_all(
        from(t in BehaviorGroup, where: t.name == ^orc),
        set: [
          behaviors: [
            %{
              "trigger" => "player_entered",
              "actions" => [%{"type" => "say", "text" => "CHANGED"}]
            }
          ]
        ]
      )

    after_edit = Repo.get_by(NPCClone, blueprint_id: slug)

    assert after_edit.behaviors == before.behaviors
    assert after_edit.behaviors == [@orc_emote, @shop_say, @direct_bye]
  end
end
