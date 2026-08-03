defmodule AgenticRealms.World.PlayerStateProjectorCharacterTest do
  @moduledoc """
  The `CharacterCreated` projector clause.

  It upserts, so it must work whether or not `PlayerSpawned` has already
  created the row: a replay from position 0 can deliver the two in either
  order. Re-handling must be a no-op, and must not clobber anything the other
  clauses own.
  """
  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.Events.{CharacterCreated, PlayerSpawned}
  alias AgenticRealms.World.Projections.PlayerStateProjector
  alias AgenticRealms.World.Schemas.PlayerState

  defp register_player do
    suffix = System.unique_integer([:positive])
    {:ok, p} = Accounts.register_player(%{username: "proj_#{suffix}", password: "pw12345678"})
    p
  end

  defp created_event(player_id, overrides \\ %{}) do
    Map.merge(
      %CharacterCreated{
        player_id: player_id,
        character_name: "Gandalf",
        species_slug: "human",
        class_slug: "fighter",
        background_slug: "soldier",
        size: "medium",
        abilities: %{str: 17, dex: 13, con: 15, int: 12, wis: 10, cha: 8},
        skill_proficiencies: ["athletics", "perception"],
        save_proficiencies: ["con", "str"],
        feat_slugs: ["alert"],
        lineage_slug: nil,
        choices: %{"feature:Fighting Style" => ["defense"]},
        hp: 12,
        max_hp: 12
      },
      overrides
    )
  end

  defp row(player_id), do: Repo.get(PlayerState, player_id)

  describe "on a row that does not exist yet" do
    test "inserts the whole character" do
      player = register_player()

      :ok = PlayerStateProjector.handle(created_event(player.id), %{})

      ps = row(player.id)
      assert ps.species_slug == "human"
      assert ps.class_slug == "fighter"
      assert ps.background_slug == "soldier"
      assert ps.size == "medium"
      assert {ps.str, ps.dex, ps.con, ps.int, ps.wis, ps.cha} == {17, 13, 15, 12, 10, 8}
      assert ps.level == 1
      assert ps.xp == 0
      assert ps.hp == 12
      assert ps.max_hp == 12
      assert ps.skill_proficiencies == ["athletics", "perception"]
      assert ps.save_proficiencies == ["con", "str"]
      assert ps.feat_slugs == ["alert"]
    end

    test "leaves the current room unset — that is PlayerSpawned's business" do
      player = register_player()

      :ok = PlayerStateProjector.handle(created_event(player.id), %{})

      assert row(player.id).current_room_id == nil
    end
  end

  describe "on a row PlayerSpawned already made" do
    setup do
      player = register_player()

      room =
        Repo.insert!(%AgenticRealms.World.Schemas.Room{
          id: Ecto.UUID.generate(),
          name: "Hall",
          description: "A hall.",
          region_id: AgenticRealms.DataCase.insert_test_region()
        })

      Repo.insert!(%PlayerState{
        player_id: player.id,
        current_room_id: room.id,
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      %{player: player, room: room}
    end

    test "fills in the character without disturbing the room", %{player: player, room: room} do
      :ok = PlayerStateProjector.handle(created_event(player.id), %{})

      ps = row(player.id)
      assert ps.species_slug == "human"
      assert ps.current_room_id == room.id
    end
  end

  describe "idempotency" do
    test "re-handling the same event changes nothing" do
      player = register_player()
      event = created_event(player.id)

      :ok = PlayerStateProjector.handle(event, %{})
      first = row(player.id)

      :ok = PlayerStateProjector.handle(event, %{})
      again = row(player.id)

      assert %{first | updated_at: nil} == %{again | updated_at: nil}
    end

    test "does not reset earned progression" do
      player = register_player()
      event = created_event(player.id)

      :ok = PlayerStateProjector.handle(event, %{})
      Repo.update_all(PlayerState, set: [level: 7, xp: 23_000])

      :ok = PlayerStateProjector.handle(event, %{})

      ps = row(player.id)
      assert ps.level == 7
      assert ps.xp == 23_000
    end
  end

  describe "event-store round trip" do
    test "abilities with string keys are normalized" do
      player = register_player()

      event =
        created_event(player.id, %{
          abilities: %{
            "str" => 17,
            "dex" => 13,
            "con" => 15,
            "int" => 12,
            "wis" => 10,
            "cha" => 8
          }
        })

      :ok = PlayerStateProjector.handle(event, %{})

      ps = row(player.id)
      assert {ps.str, ps.dex, ps.con, ps.int, ps.wis, ps.cha} == {17, 13, 15, 12, 10, 8}
    end
  end

  describe "PlayerSpawned after CharacterCreated" do
    @tag :commanded
    test "does not reset the character" do
      player = register_player()

      room =
        Repo.insert!(%AgenticRealms.World.Schemas.Room{
          id: Ecto.UUID.generate(),
          name: "Hall",
          description: "A hall.",
          region_id: AgenticRealms.DataCase.insert_test_region()
        })

      :ok = PlayerStateProjector.handle(created_event(player.id), %{})

      :ok =
        PlayerStateProjector.handle(%PlayerSpawned{player_id: player.id, room_id: room.id}, %{})

      ps = row(player.id)
      assert ps.current_room_id == room.id
      assert ps.species_slug == "human"
      assert ps.str == 17
    end
  end

  describe "feature 021 — the player's own choices reach the row" do
    test "the name, lineage, and choices map round-trip through the event" do
      player = register_player()

      :ok =
        PlayerStateProjector.handle(
          created_event(player.id, %{
            character_name: "Legolas",
            lineage_slug: "wood-elf",
            choices: %{
              "feature:Weapon Mastery" => ["longbow", "shortsword"],
              "background_tool" => ["dice-set"]
            }
          }),
          %{}
        )

      ps = row(player.id)

      assert ps.character_name == "Legolas"
      assert ps.lineage_slug == "wood-elf"
      assert ps.choices["feature:Weapon Mastery"] == ["longbow", "shortsword"]
      assert ps.choices["background_tool"] == ["dice-set"]
    end

    test "a species with no lineage stores nil rather than a placeholder" do
      player = register_player()

      :ok = PlayerStateProjector.handle(created_event(player.id, %{lineage_slug: nil}), %{})

      assert row(player.id).lineage_slug == nil
    end

    test "an empty choices map is stored as an empty map, not null" do
      player = register_player()

      :ok = PlayerStateProjector.handle(created_event(player.id, %{choices: %{}}), %{})

      assert row(player.id).choices == %{}
    end

    test "re-handling replaces the choices rather than merging them" do
      player = register_player()
      event = created_event(player.id, %{choices: %{"a" => ["one"]}})

      :ok = PlayerStateProjector.handle(event, %{})
      :ok = PlayerStateProjector.handle(event, %{})

      assert row(player.id).choices == %{"a" => ["one"]}
    end
  end
end
