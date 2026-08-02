defmodule AgenticRealms.World.PlayerNamesTest do
  @moduledoc """
  Feature 021 — the one place the world asks what a player is called.

  Reads `player_state.character_name`, never `accounts.players.username`. A
  `nil` means "no character yet", which is what GameLive's mount branches on.
  """
  use AgenticRealms.DataCase, async: true

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.PlayerNames
  alias AgenticRealms.World.Schemas.PlayerState

  defp register_player do
    suffix = System.unique_integer([:positive])

    {:ok, player} =
      Accounts.register_player(%{username: "namer_#{suffix}", password: "pw12345678"})

    player.id
  end

  # A projected row for a real account. `player_state.player_id` carries a
  # foreign key, so the account has to exist first.
  defp player_row(name) do
    id = register_player()

    Repo.insert!(%PlayerState{
      player_id: id,
      character_name: name,
      species_slug: "human",
      class_slug: "fighter",
      background_slug: "soldier",
      size: "medium",
      str: 15,
      dex: 13,
      con: 14,
      int: 12,
      wis: 10,
      cha: 8,
      level: 1,
      xp: 0,
      hp: 12,
      max_hp: 12
    }).player_id
  end

  describe "get/1" do
    test "returns nil for a player with no row at all" do
      assert PlayerNames.get(register_player()) == nil
    end

    test "returns nil for a row that has no character yet" do
      assert PlayerNames.get(player_row(nil)) == nil
    end

    test "returns the character name once there is one" do
      assert PlayerNames.get(player_row("Gandalf")) == "Gandalf"
    end

    test "returns the name as typed, not normalized" do
      assert PlayerNames.get(player_row("aRaGoRn")) == "aRaGoRn"
    end
  end

  describe "get_many/1" do
    test "returns a map keyed by player id" do
      frodo = player_row("Frodo")
      sam = player_row("Samwise")

      assert PlayerNames.get_many([frodo, sam]) == %{frodo => "Frodo", sam => "Samwise"}
    end

    test "omits players with no character rather than mapping them to nil" do
      merry = player_row("Merry")
      uncreated = player_row(nil)
      no_row = register_player()

      assert PlayerNames.get_many([merry, uncreated, no_row]) == %{merry => "Merry"}
    end

    test "an empty list needs no query and returns an empty map" do
      assert PlayerNames.get_many([]) == %{}
    end
  end

  describe "find_by_name/1" do
    test "finds a player by their exact name" do
      id = player_row("Legolas")
      assert PlayerNames.find_by_name("Legolas") == id
    end

    test "matches regardless of case" do
      id = player_row("Gimli")

      assert PlayerNames.find_by_name("gimli") == id
      assert PlayerNames.find_by_name("GIMLI") == id
      assert PlayerNames.find_by_name("GiMlI") == id
    end

    test "ignores surrounding whitespace" do
      id = player_row("Boromir")
      assert PlayerNames.find_by_name("  boromir  ") == id
    end

    test "returns nil when no character holds the name" do
      assert PlayerNames.find_by_name("Sauron") == nil
    end

    test "returns nil for a blank name rather than matching an uncreated row" do
      player_row(nil)

      assert PlayerNames.find_by_name("") == nil
      assert PlayerNames.find_by_name("   ") == nil
    end
  end

  describe "taken?/1" do
    test "reports whether a name is already held, ignoring case" do
      player_row("Arwen")

      assert PlayerNames.taken?("arwen")
      refute PlayerNames.taken?("Eowyn")
    end
  end

  describe "normalize/1" do
    test "trims and downcases, which is how two names are compared" do
      assert PlayerNames.normalize("  Gandalf  ") == "gandalf"
      assert PlayerNames.normalize("GANDALF") == "gandalf"
    end
  end
end
