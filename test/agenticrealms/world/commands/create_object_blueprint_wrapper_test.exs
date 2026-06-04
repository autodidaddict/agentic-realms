defmodule AgenticRealms.World.Commands.CreateObjectBlueprintWrapperTest do
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Commands
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.ObjectBlueprint

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wiz_#{suffix}", password: "pw12345678"})

    {:ok, non_wizard} =
      Accounts.register_player(%{username: "nw_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)

    %{wizard: wizard, non_wizard: non_wizard, suffix: suffix}
  end

  test "happy path creates a blueprint and persists the row at revision 1",
       %{wizard: wizard, suffix: suffix} do
    slug = "brass_chest_#{suffix}"

    assert {:ok, ^slug} =
             Commands.create_object_blueprint(%{
               wizard_id: wizard.id,
               blueprint_id: slug,
               name: "brass chest",
               short_description: "a brass-bound chest",
               long_description: "A weather-beaten brass-bound chest.",
               fixed: true
             })

    assert %ObjectBlueprint{
             id: ^slug,
             kind: "object",
             revision: 1,
             name: "brass chest",
             fixed: true
           } = Queries.get_object_blueprint(slug)
  end

  test "refuses non-wizard caller without dispatching",
       %{non_wizard: nw, suffix: suffix} do
    slug = "non_wiz_attempt_#{suffix}"

    assert {:error, :not_a_wizard} =
             Commands.create_object_blueprint(%{
               wizard_id: nw.id,
               blueprint_id: slug,
               name: "x",
               short_description: "y",
               long_description: "z"
             })

    assert is_nil(Repo.get(ObjectBlueprint, slug))
  end

  test "refuses unknown wizard_id",
       %{suffix: suffix} do
    slug = "unknown_attempt_#{suffix}"

    assert {:error, :unknown_player} =
             Commands.create_object_blueprint(%{
               wizard_id: 999_999_999,
               blueprint_id: slug,
               name: "x",
               short_description: "y",
               long_description: "z"
             })

    assert is_nil(Repo.get(ObjectBlueprint, slug))
  end

  test "refuses invalid slug shape",
       %{wizard: wizard} do
    assert {:error, :invalid_slug} =
             Commands.create_object_blueprint(%{
               wizard_id: wizard.id,
               blueprint_id: "Has-Hyphens-And-Caps",
               name: "x",
               short_description: "y",
               long_description: "z"
             })
  end

  test "refuses colliding slug",
       %{wizard: wizard, suffix: suffix} do
    slug = "collide_#{suffix}"

    {:ok, ^slug} =
      Commands.create_object_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: slug,
        name: "first",
        short_description: "y",
        long_description: "z"
      })

    assert {:error, :slug_already_exists} =
             Commands.create_object_blueprint(%{
               wizard_id: wizard.id,
               blueprint_id: slug,
               name: "second",
               short_description: "y",
               long_description: "z"
             })
  end
end
