defmodule AgenticRealms.World.PlayerCreateCharacterTest do
  @moduledoc """
  Feature 020 — Player aggregate CreateCharacter: emits once, then never again.

  Pure — no database, no Commanded.
  """
  use ExUnit.Case, async: true

  alias AgenticRealms.World.Player
  alias AgenticRealms.World.Commands.CreateCharacter
  alias AgenticRealms.World.Events.{CharacterCreated, PlayerSpawned}

  @abilities %{str: 17, dex: 13, con: 15, int: 12, wis: 10, cha: 8}
  @skills ["acrobatics", "athletics", "history", "intimidation", "perception"]
  @saves ["con", "str"]
  @feats ["alert", "savage-attacker"]

  defp cmd do
    %CreateCharacter{
      player_id: 1,
      species_slug: "human",
      class_slug: "fighter",
      background_slug: "soldier",
      size: "medium",
      abilities: @abilities,
      skill_proficiencies: @skills,
      save_proficiencies: @saves,
      feat_slugs: @feats,
      max_hp: 12
    }
  end

  defp created(state \\ %Player{}) do
    Player.apply(state, Player.execute(state, cmd()))
  end

  describe "execute/2" do
    test "a fresh player gets a CharacterCreated carrying the whole character" do
      assert %CharacterCreated{
               player_id: 1,
               species_slug: "human",
               class_slug: "fighter",
               background_slug: "soldier",
               size: "medium",
               abilities: @abilities,
               skill_proficiencies: @skills,
               save_proficiencies: @saves,
               feat_slugs: @feats,
               hp: 12,
               max_hp: 12
             } = Player.execute(%Player{}, cmd())
    end

    test "a character is created at full health" do
      event = Player.execute(%Player{}, cmd())

      assert event.hp == event.max_hp
    end

    test "a second dispatch is a no-op" do
      assert :ok = Player.execute(created(), cmd())
    end

    test "is idempotent however many times it is dispatched" do
      state = created()

      assert :ok = Player.execute(state, cmd())
      assert :ok = Player.execute(state, cmd())
    end

    test "creating after spawning still works" do
      spawned = Player.apply(%Player{}, %PlayerSpawned{player_id: 1, room_id: "room-1"})

      assert %CharacterCreated{} = Player.execute(spawned, cmd())
    end
  end

  describe "apply/2" do
    test "records the whole character on the aggregate" do
      state = created()

      assert state.species_slug == "human"
      assert state.class_slug == "fighter"
      assert state.background_slug == "soldier"
      assert state.size == "medium"
      assert state.skill_proficiencies == @skills
      assert state.save_proficiencies == @saves
      assert state.feat_slugs == @feats
    end

    test "seeds the ability scores, level, experience and hitpoints" do
      state = created()

      assert {state.str, state.dex, state.con} == {17, 13, 15}
      assert {state.int, state.wis, state.cha} == {12, 10, 8}
      assert state.level == 1
      assert state.xp == 0
      assert state.hp == 12
      assert state.max_hp == 12
    end

    test "normalizes a string-keyed abilities map from a JSON round trip" do
      event =
        %Player{}
        |> Player.execute(cmd())
        |> Map.put(:abilities, %{
          "str" => 17,
          "dex" => 13,
          "con" => 15,
          "int" => 12,
          "wis" => 10,
          "cha" => 8
        })

      state = Player.apply(%Player{}, event)

      assert {state.str, state.dex, state.con} == {17, 13, 15}
      assert {state.int, state.wis, state.cha} == {12, 10, 8}
    end

    test "a re-applied event leaves the same state" do
      state = created()

      assert Player.apply(state, Player.execute(%Player{}, cmd())) == state
    end
  end

  describe "PlayerSpawned" do
    test "no longer seeds any stats — a character is what carries them" do
      state = Player.apply(%Player{}, %PlayerSpawned{player_id: 1, room_id: "room-1"})

      assert state.id == 1
      assert state.current_room_id == "room-1"
      assert state.str == nil
      assert state.level == nil
      assert state.hp == nil
      assert state.species_slug == nil
    end

    test "spawning after creating does not disturb the character" do
      state =
        created()
        |> Player.apply(%PlayerSpawned{player_id: 1, room_id: "room-1"})

      assert state.current_room_id == "room-1"
      assert state.species_slug == "human"
      assert state.str == 17
      assert state.level == 1
    end
  end
end
