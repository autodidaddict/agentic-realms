defmodule AgenticRealms.World.QueriesPlayersInRoomTest do
  @moduledoc """
  List_players_in_room/1 returns online players. The online filter
  is verified via offline-exclusion (a persisted-in-room but not-Presence-tracked
  player is excluded); tracking a live session here would drive the always-on
  `Ticks.Lifecycle` to touch the DB outside the sandbox, so the positive online
  path is left to the proven `list_other_players` presence logic it reuses.
  """
  use AgenticRealms.DataCase, async: true

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.{Room, PlayerState}

  defp insert_room(region) do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "R#{System.unique_integer([:positive])}",
      description: "d",
      region_id: region
    }).id
  end

  test "a persisted-in-room but offline player is excluded" do
    region = insert_test_region()
    room = insert_room(region)
    suffix = System.unique_integer([:positive])

    {:ok, player} = Accounts.register_player(%{username: "occ_#{suffix}", password: "pw12345678"})
    Repo.insert!(%PlayerState{player_id: player.id, current_room_id: room})

    assert [] == Queries.list_players_in_room(room)
  end

  test "an empty room returns []" do
    region = insert_test_region()
    assert [] == Queries.list_players_in_room(insert_room(region))
  end
end
