defmodule AgenticRealms.World.Commands.CreateNPCBlueprintWrapperTest do
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Commands
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.{Blueprint, BehaviorGroup}

  @greeter %{
    "trigger" => "player_entered",
    "actions" => [%{"type" => "say", "text" => "Welcome, traveller."}]
  }

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wiz_#{suffix}", password: "pw12345678"})

    {:ok, non_wizard} =
      Accounts.register_player(%{username: "nw_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%BehaviorGroup{
      name: "greeter",
      behaviors: [@greeter],
      applies_to: ["npc"],
      inserted_at: now,
      updated_at: now
    })

    %{wizard: wizard, non_wizard: non_wizard, suffix: suffix}
  end

  test "happy path persists an npc-kind row at revision 1 with behavior_groups + fixed",
       %{wizard: wizard, suffix: suffix} do
    slug = "cave_troll_#{suffix}"

    assert {:ok, ^slug} =
             Commands.create_npc_blueprint(%{
               wizard_id: wizard.id,
               blueprint_id: slug,
               name: "Cave Troll",
               short_description: "a hulking cave troll",
               long_description: "A mountain of grey muscle and warty hide.",
               lore: "Hates sunlight.",
               fixed: true,
               behavior_groups: ["greeter"]
             })

    assert %Blueprint{
             id: ^slug,
             kind: "npc",
             revision: 1,
             name: "Cave Troll",
             fixed: true,
             behavior_groups: ["greeter"],
             lore: "Hates sunlight."
           } = Queries.get_npc_blueprint_row(slug)
  end

  test "refuses a non-wizard caller without dispatching",
       %{non_wizard: nw, suffix: suffix} do
    slug = "nw_npc_#{suffix}"

    assert {:error, :not_a_wizard} =
             Commands.create_npc_blueprint(%{
               wizard_id: nw.id,
               blueprint_id: slug,
               name: "x",
               short_description: "y",
               long_description: "z"
             })

    assert is_nil(Repo.get(Blueprint, slug))
  end

  test "refuses an invalid slug shape", %{wizard: wizard} do
    assert {:error, :invalid_slug} =
             Commands.create_npc_blueprint(%{
               wizard_id: wizard.id,
               blueprint_id: "Has-Hyphens",
               name: "x",
               short_description: "y",
               long_description: "z"
             })
  end

  test "slug uniqueness spans the object registry",
       %{wizard: wizard, suffix: suffix} do
    slug = "shared_slug_#{suffix}"

    {:ok, ^slug} =
      Commands.create_object_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: slug,
        name: "an object",
        short_description: "y",
        long_description: "z"
      })

    assert {:error, :slug_already_exists} =
             Commands.create_npc_blueprint(%{
               wizard_id: wizard.id,
               blueprint_id: slug,
               name: "an npc",
               short_description: "y",
               long_description: "z"
             })

    assert %Blueprint{kind: "object"} = Repo.get(Blueprint, slug)
  end

  test "an object cannot reuse an npc slug (reverse direction)",
       %{wizard: wizard, suffix: suffix} do
    slug = "npc_first_#{suffix}"

    {:ok, ^slug} =
      Commands.create_npc_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: slug,
        name: "an npc",
        short_description: "y",
        long_description: "z"
      })

    assert {:error, :slug_already_exists} =
             Commands.create_object_blueprint(%{
               wizard_id: wizard.id,
               blueprint_id: slug,
               name: "an object",
               short_description: "y",
               long_description: "z"
             })

    assert %Blueprint{kind: "npc"} = Repo.get(Blueprint, slug)
  end

  test "refuses an unknown behavior_group name",
       %{wizard: wizard, suffix: suffix} do
    slug = "ghost_behavior_group_#{suffix}"

    assert {:error, {:unknown_behavior_group, "ghost"}} =
             Commands.create_npc_blueprint(%{
               wizard_id: wizard.id,
               blueprint_id: slug,
               name: "x",
               short_description: "y",
               long_description: "z",
               behavior_groups: ["ghost"]
             })

    assert is_nil(Repo.get(Blueprint, slug))
  end

  test "refuses a direct behavior outside the feature-009 vocabulary",
       %{wizard: wizard, suffix: suffix} do
    slug = "bad_behavior_#{suffix}"

    bad = [%{"trigger" => "on_examine", "actions" => [%{"type" => "say", "text" => "x"}]}]

    assert {:error, _} =
             Commands.create_npc_blueprint(%{
               wizard_id: wizard.id,
               blueprint_id: slug,
               name: "x",
               short_description: "y",
               long_description: "z",
               behaviors: bad
             })

    assert is_nil(Repo.get(Blueprint, slug))
  end
end
