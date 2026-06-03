defmodule AgenticRealms.World.Commands.EditObjectBlueprintWrapperTest do
  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.{Commands, Queries, Seed}

  setup do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wed_#{suffix}", password: "pw12345678"})

    {:ok, non_wizard} =
      Accounts.register_player(%{username: "ned_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)

    slug = "edit_test_#{suffix}"

    {:ok, ^slug} =
      Commands.create_object_blueprint(%{
        wizard_id: wizard.id,
        blueprint_id: slug,
        name: "edit test",
        short_description: "a small thing",
        long_description: "A small thing for testing edits."
      })

    %{wizard: wizard, non_wizard: non_wizard, slug: slug}
  end

  test "happy path: field-changing edit bumps revision to N+1", %{wizard: w, slug: slug} do
    bp_before = Queries.get_object_blueprint(slug)
    assert bp_before.revision == 1

    assert {:ok, 2} =
             Commands.edit_object_blueprint(w.id, slug, %{
               expected_revision: 1,
               fields_changed: %{short_description: "an edited thing"}
             })

    bp_after = Queries.get_object_blueprint(slug)
    assert bp_after.revision == 2
    assert bp_after.short_description == "an edited thing"
    assert bp_after.name == bp_before.name
  end

  test "no-op diff returns {:ok, :no_change}; revision is NOT bumped",
       %{wizard: w, slug: slug} do
    bp_before = Queries.get_object_blueprint(slug)

    assert {:ok, :no_change} =
             Commands.edit_object_blueprint(w.id, slug, %{
               expected_revision: 1,
               fields_changed: %{name: bp_before.name, short_description: bp_before.short_description}
             })

    bp_after = Queries.get_object_blueprint(slug)
    assert bp_after.revision == bp_before.revision
  end

  test "stale revision returns :stale_revision with current revision",
       %{wizard: w, slug: slug} do
    # First edit bumps revision to 2.
    {:ok, 2} =
      Commands.edit_object_blueprint(w.id, slug, %{
        expected_revision: 1,
        fields_changed: %{short_description: "first edit"}
      })

    # Second edit using stale expected_revision: 1 → :stale_revision.
    assert {:error, :stale_revision, current_revision: 2} =
             Commands.edit_object_blueprint(w.id, slug, %{
               expected_revision: 1,
               fields_changed: %{short_description: "stale edit"}
             })

    # The Blueprint's actual state should NOT have been modified by the
    # rejected edit.
    bp = Queries.get_object_blueprint(slug)
    assert bp.short_description == "first edit"
  end

  test "non-wizard caller is refused", %{non_wizard: nw, slug: slug} do
    assert {:error, :not_a_wizard} =
             Commands.edit_object_blueprint(nw.id, slug, %{
               expected_revision: 1,
               fields_changed: %{name: "x"}
             })
  end

  test "unknown blueprint is refused", %{wizard: w} do
    assert {:error, :unknown_blueprint} =
             Commands.edit_object_blueprint(w.id, "no_such_thing", %{
               expected_revision: 1,
               fields_changed: %{name: "x"}
             })
  end

  test "invalid field key is refused", %{wizard: w, slug: slug} do
    assert {:error, :invalid_field} =
             Commands.edit_object_blueprint(w.id, slug, %{
               expected_revision: 1,
               fields_changed: %{behaviors: [], some_garbage_field: 1}
             })
  end

  test "previously-spawned clones reflect the OLD revision values (FR-021)",
       %{wizard: w, slug: slug} do
    {:ok, object_id} =
      Commands.spawn_object_from_blueprint(w.id, slug, AgenticRealms.World.Seed.starting_room_id())

    # Edit the blueprint AFTER spawning.
    {:ok, 2} =
      Commands.edit_object_blueprint(w.id, slug, %{
        expected_revision: 1,
        fields_changed: %{short_description: "edited after spawn"}
      })

    # The already-spawned clone keeps its original short_description.
    clone = AgenticRealms.Repo.get(AgenticRealms.World.Schemas.Object, object_id)
    assert clone.short_description == "a small thing"
  end
end
