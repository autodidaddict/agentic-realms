defmodule AgenticRealmsWeb.StatsChangedTest do
  @moduledoc """
  How the open character sheet reacts to progression.

  An xp-only change is patched from the broadcast payload with no database
  read. A level change re-derives the whole sheet, because level moves the
  proficiency bonus, hitpoint maximum, hit dice, and every proficient save and
  skill — none of which the payload carries.
  """
  use AgenticRealms.DataCase, async: false

  alias AgenticRealms.Accounts
  alias AgenticRealms.DataCase
  alias AgenticRealms.World.Stats
  alias AgenticRealms.World.Schemas.PlayerState
  alias AgenticRealms.World.UIEvents.PlayerStatsChanged
  alias AgenticRealmsWeb.GameLive.UIEvents

  defp player_with_character(overrides \\ []) do
    suffix = System.unique_integer([:positive])

    {:ok, p} =
      Accounts.register_player(%{username: "stats_#{suffix}", password: "pw12345678"})

    Repo.insert!(struct!(PlayerState, [player_id: p.id] ++ DataCase.character_columns(overrides)))
    p
  end

  defp socket_for(player) do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:current_player, player)
    |> Phoenix.Component.assign(:stats, Stats.for_player(player.id))
    |> Phoenix.Component.assign(:log, [])
  end

  describe "an experience-only change" do
    test "patches the bar from the payload" do
      player = player_with_character()
      socket = socket_for(player)

      {:noreply, socket} =
        UIEvents.stats_changed(socket, %PlayerStatsChanged{
          player_id: player.id,
          xp_gained: 120,
          new_total: 120,
          leveled_to: nil
        })

      assert socket.assigns.stats.xp.into_level == 120
      assert socket.assigns.stats.xp.total == 120
      assert socket.assigns.stats.xp.to_next == 300
      refute socket.assigns.stats.xp.maxed?
      assert socket.assigns.stats.level == 1
    end

    test "does not read the database" do
      player = player_with_character()
      socket = socket_for(player)

      Repo.delete_all(PlayerState)

      {:noreply, socket} =
        UIEvents.stats_changed(socket, %PlayerStatsChanged{
          player_id: player.id,
          xp_gained: 50,
          new_total: 50,
          leveled_to: nil
        })

      assert socket.assigns.stats.xp.into_level == 50
    end

    test "appends the gain notice" do
      player = player_with_character()
      socket = socket_for(player)

      {:noreply, socket} =
        UIEvents.stats_changed(socket, %PlayerStatsChanged{
          player_id: player.id,
          xp_gained: 120,
          new_total: 120,
          leveled_to: nil
        })

      assert Enum.any?(socket.assigns.log, &(&1[:text] == "You gain 120 experience."))
    end
  end

  describe "a level change" do
    test "re-derives everything the new level moves" do
      player = player_with_character()
      socket = socket_for(player)

      assert socket.assigns.stats.proficiency_bonus == 2
      assert socket.assigns.stats.hp.max == 12

      Repo.update_all(PlayerState, set: [level: 5, xp: 6_500])

      {:noreply, socket} =
        UIEvents.stats_changed(socket, %PlayerStatsChanged{
          player_id: player.id,
          xp_gained: nil,
          new_total: nil,
          leveled_to: 5
        })

      stats = socket.assigns.stats

      assert stats.level == 5
      assert stats.proficiency_bonus == 3
      assert stats.hp.max == 44
      assert stats.hit_dice.count == 5

      athletics = Enum.find(stats.skills, &(&1.key == :athletics))
      assert athletics.modifier == 6
    end

    test "appends the level notice" do
      player = player_with_character()
      socket = socket_for(player)
      Repo.update_all(PlayerState, set: [level: 2, xp: 300])

      {:noreply, socket} =
        UIEvents.stats_changed(socket, %PlayerStatsChanged{
          player_id: player.id,
          xp_gained: 300,
          new_total: 300,
          leveled_to: 2
        })

      assert Enum.any?(socket.assigns.log, &(&1[:text] == "You are now level 2!"))
      assert Enum.any?(socket.assigns.log, &(&1[:text] == "You gain 300 experience."))
    end

    test "at the cap the sheet reports fully levelled" do
      player = player_with_character(level: 20, xp: 355_000)
      socket = socket_for(player)

      Repo.update_all(PlayerState, set: [xp: 400_000])

      {:noreply, socket} =
        UIEvents.stats_changed(socket, %PlayerStatsChanged{
          player_id: player.id,
          xp_gained: 45_000,
          new_total: 400_000,
          leveled_to: 20
        })

      assert socket.assigns.stats.xp.maxed?
      assert socket.assigns.stats.xp.to_next == nil
    end
  end
end
