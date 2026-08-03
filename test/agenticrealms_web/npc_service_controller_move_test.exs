defmodule AgenticRealmsWeb.NpcServiceControllerMoveTest do
  @moduledoc "POST /api/npc/:id/move (compare-and-swap, witnessed)."
  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :commanded

  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Commands, ContainerRef}
  alias AgenticRealms.World.Schemas.NPCClone

  @secret "test-npc-secret"

  defp auth(conn) do
    conn
    |> put_req_header("authorization", "Bearer #{@secret}")
    |> put_req_header("accept", "application/json")
  end

  defp npc_fields(name) do
    %{
      blueprint_id: nil,
      name: name,
      short_description: "s",
      long_description: "l",
      behaviors: [],
      direct_behaviors: [],
      behavior_groups: [],
      lore: "",
      fixed: false
    }
  end

  setup do
    region = AgenticRealms.DataCase.insert_test_region()
    room_a = Ecto.UUID.generate()
    room_b = Ecto.UUID.generate()
    room_c = Ecto.UUID.generate()
    :ok = Commands.create_room(room_a, "A", "d", region)
    :ok = Commands.create_room(room_b, "B", "d", region)
    :ok = Commands.create_room(room_c, "C", "d", region)
    :ok = Commands.add_exit(room_a, :north, room_b)

    {:ok, npc} =
      Commands.clone_into(:npc, npc_fields("Grik"), ContainerRef.room(room_a), :spawned)

    %{npc: npc, room_a: room_a, room_b: room_b, room_c: room_c}
  end

  test "a valid move relocates the NPC and returns ok with rooms", %{
    conn: conn,
    npc: npc,
    room_a: a,
    room_b: b
  } do
    conn =
      conn |> auth() |> post(~p"/api/npc/#{npc}/move", %{direction: "north", expected_room_id: a})

    assert %{"result" => "ok", "from_room_id" => ^a, "to_room_id" => ^b} =
             json_response(conn, 200)

    assert Repo.get(NPCClone, npc).room_id == b
  end

  test "a stale expected_room_id → 409 conflict, no relocation", %{
    conn: conn,
    npc: npc,
    room_a: a,
    room_c: c
  } do
    :ok = Commands.move_entity(npc, ContainerRef.room(a), ContainerRef.room(c), :relocated)
    assert Repo.get(NPCClone, npc).room_id == c

    conn =
      conn |> auth() |> post(~p"/api/npc/#{npc}/move", %{direction: "north", expected_room_id: a})

    assert %{"result" => "conflict"} = json_response(conn, 409)
    assert Repo.get(NPCClone, npc).room_id == c
  end

  test "a direction that is not an exit → 422 no_such_exit", %{conn: conn, npc: npc, room_a: a} do
    conn =
      conn |> auth() |> post(~p"/api/npc/#{npc}/move", %{direction: "west", expected_room_id: a})

    assert %{"result" => "no_such_exit"} = json_response(conn, 422)
  end

  test "an unknown NPC → 404", %{conn: conn, room_a: a} do
    conn =
      conn
      |> auth()
      |> post(~p"/api/npc/#{Ecto.UUID.generate()}/move", %{
        direction: "north",
        expected_room_id: a
      })

    assert json_response(conn, 404)
  end

  test "missing token → 401 before any move", %{npc: npc, room_a: a} do
    conn =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/npc/#{npc}/move", %{direction: "north", expected_room_id: a})

    assert json_response(conn, 401)
    assert Repo.get(NPCClone, npc).room_id == a
  end
end
