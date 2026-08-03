defmodule AgenticRealmsWeb.NpcServiceControllerSurroundingsTest do
  @moduledoc "GET /api/npc/:id/surroundings."
  use AgenticRealmsWeb.ConnCase, async: true

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Schemas.{Room, Exit, NPCClone, Object}

  @secret "test-npc-secret"

  defp auth(conn) do
    conn
    |> put_req_header("authorization", "Bearer #{@secret}")
    |> put_req_header("accept", "application/json")
  end

  defp insert_room(region) do
    Repo.insert!(%Room{
      id: Ecto.UUID.generate(),
      name: "R#{System.unique_integer([:positive])}",
      description: "d",
      region_id: region
    }).id
  end

  test "reports the room, its global exits, and occupants tagged by kind", %{conn: conn} do
    region = AgenticRealms.DataCase.insert_test_region()
    room = insert_room(region)
    north = insert_room(region)

    Repo.insert!(%Exit{direction: "north", source_room_id: room, target_room_id: north})

    npc =
      Repo.insert!(%NPCClone{
        id: Ecto.UUID.generate(),
        name: "Grik",
        short_description: "s",
        long_description: "l",
        room_id: room
      })

    Repo.insert!(%Object{
      id: Ecto.UUID.generate(),
      name: "a brass lantern",
      short_description: "a brass lantern",
      long_description: "A dented brass lantern.",
      container_type: "room",
      container_id: room
    })

    conn = conn |> auth() |> get(~p"/api/npc/#{npc.id}/surroundings")
    resp = json_response(conn, 200)

    assert resp["entity_id"] == npc.id
    assert resp["room_id"] == room
    assert %{"direction" => "north", "to_room_id" => north} in resp["exits"]

    assert %{"id" => npc.id, "kind" => "npc", "name" => "Grik"} in resp["occupants"]

    assert Enum.any?(
             resp["occupants"],
             &(&1["kind"] == "object" and &1["name"] == "a brass lantern")
           )
  end

  test "a void/removed NPC returns a well-formed empty snapshot", %{conn: conn} do
    npc =
      Repo.insert!(%NPCClone{
        id: Ecto.UUID.generate(),
        name: "Void",
        short_description: "s",
        long_description: "l",
        room_id: nil
      })

    conn = conn |> auth() |> get(~p"/api/npc/#{npc.id}/surroundings")

    assert %{"entity_id" => _, "room_id" => nil, "exits" => [], "occupants" => []} =
             json_response(conn, 200)
  end

  test "unknown id → 404", %{conn: conn} do
    conn = conn |> auth() |> get(~p"/api/npc/#{Ecto.UUID.generate()}/surroundings")
    assert json_response(conn, 404)
  end
end
