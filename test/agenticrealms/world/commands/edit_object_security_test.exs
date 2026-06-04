defmodule AgenticRealms.World.Commands.EditObjectSecurityTest do
  @moduledoc """
  Defense-in-depth coverage for the EditObject + ExtractObjectEssence
  wrappers, addressing the review findings from PR #30:

    * bug_002 — cross-room edit refusal.
    * bug_008 — quest-scoped object refusal.
  """

  use AgenticRealms.DataCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, Seed}
  alias AgenticRealms.World.Schemas.{Object, ObjectBlueprint}

  setup do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])

    {:ok, wizard} =
      Accounts.register_player(%{username: "wsec_#{suffix}", password: "pw12345678"})

    {:ok, _} = Accounts.promote_to_wizard(wizard.id)
    {:ok, _} = Commands.spawn(wizard.id, Seed.starting_room_id())

    %{wizard: wizard, suffix: suffix}
  end

  describe "cross-room edit refusal (bug_002 / FR contract)" do
    test "wizard who moves away from the object's room cannot edit it",
         %{wizard: w, suffix: suffix} do
      starting = Seed.starting_room_id()

      {:ok, object_id} =
        Commands.spawn_object_freeform(w.id, starting, %{
          name: "cross_room_target_#{suffix}",
          short_description: "a cross-room test pot",
          long_description: "A pot we'll try to edit from a different room."
        })

      # Walk the wizard east; the seed has an east exit out of Stone Atrium.
      {:ok, _new_room_id} = Commands.move(w.id, :east)

      assert {:error, :object_not_editable_here} =
               Commands.edit_object(w.id, object_id, %{
                 short_description: "should be refused"
               })

      # The Object's persisted short_description is unchanged.
      row = Repo.get(Object, object_id)
      assert row.short_description == "a cross-room test pot"
    end

    test "wizard who never spawned has no current_room and is refused",
         %{suffix: suffix} do
      {:ok, ghost} =
        Accounts.register_player(%{username: "ghost_#{suffix}", password: "pw12345678"})

      {:ok, _} = Accounts.promote_to_wizard(ghost.id)

      # Spawn a separate wizard and freeform an object so we have one to
      # target. We don't spawn the ghost.
      {:ok, other} =
        Accounts.register_player(%{username: "other_#{suffix}", password: "pw12345678"})

      {:ok, _} = Accounts.promote_to_wizard(other.id)
      {:ok, _} = Commands.spawn(other.id, Seed.starting_room_id())

      {:ok, object_id} =
        Commands.spawn_object_freeform(other.id, Seed.starting_room_id(), %{
          name: "ghost_target_#{suffix}",
          short_description: "a ghost-targeted pot",
          long_description: "A pot the unspawned ghost will try to edit."
        })

      assert {:error, :object_not_editable_here} =
               Commands.edit_object(ghost.id, object_id, %{name: "x"})
    end
  end

  describe "quest-scoped object refusal (bug_008)" do
    test "edit_object refuses an object whose quest_player_id is set",
         %{wizard: w, suffix: suffix} do
      {:ok, object_id} =
        Commands.spawn_object_freeform(w.id, Seed.starting_room_id(), %{
          name: "quest_target_#{suffix}",
          short_description: "a quest-scoped target",
          long_description: "A target that's about to be quest-scoped."
        })

      # Quest-scope the row via a real quest_instances row so the DB
      # check + FK constraints are satisfied.
      qi_id = insert_quest_instance(w.id)

      {1, _} =
        Repo.update_all(
          from(o in Object, where: o.id == ^object_id),
          set: [quest_player_id: w.id, quest_instance_id: qi_id]
        )

      assert {:error, :unknown_object} =
               Commands.edit_object(w.id, object_id, %{
                 short_description: "should be refused"
               })

      row = Repo.get(Object, object_id)
      assert row.short_description == "a quest-scoped target"
    end

    test "extract_object_essence refuses an object whose quest_player_id is set",
         %{wizard: w, suffix: suffix} do
      {:ok, object_id} =
        Commands.spawn_object_freeform(w.id, Seed.starting_room_id(), %{
          name: "quest_extract_#{suffix}",
          short_description: "a quest-scoped extract source",
          long_description: "A source the wizard tries to extract from."
        })

      qi_id = insert_quest_instance(w.id)

      {1, _} =
        Repo.update_all(
          from(o in Object, where: o.id == ^object_id),
          set: [quest_player_id: w.id, quest_instance_id: qi_id]
        )

      slug = "quest_extract_attempt_#{suffix}"

      assert {:error, :unknown_object} =
               Commands.extract_object_essence(w.id, object_id, slug)

      # No blueprint persisted.
      assert is_nil(Repo.get(ObjectBlueprint, slug))
    end
  end

  # --- Helpers ------------------------------------------------------------

  import Ecto.Query

  # Seeds a minimal quest_instances row anchored to the seeded
  # innkeeper blueprint, so we can quest-scope a world Object via raw
  # Repo writes without going through the full AcceptQuest flow.
  defp insert_quest_instance(player_id) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %AgenticRealms.World.Schemas.QuestInstance{
      id: id,
      player_id: player_id,
      npc_blueprint_id: "garrick_the_innkeeper",
      slug: "test_quest_#{System.unique_integer([:positive])}",
      state: "active",
      accepted_at: now,
      definition_snapshot: %{}
    }
    |> Repo.insert!()

    id
  end
end
