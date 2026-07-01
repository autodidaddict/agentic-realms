defmodule AgenticRealmsWeb.NpcServiceControllerIdentityTest do
  @moduledoc "Feature 018 — GET /api/npc/:id/identity."
  use AgenticRealmsWeb.ConnCase, async: true

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Schemas.NPCClone

  @secret "test-npc-secret"

  defp auth(conn) do
    conn
    |> put_req_header("authorization", "Bearer #{@secret}")
    |> put_req_header("accept", "application/json")
  end

  test "returns the NPC's identity + lore", %{conn: conn} do
    npc =
      Repo.insert!(%NPCClone{
        id: Ecto.UUID.generate(),
        name: "Garrick the Innkeeper",
        short_description: "a wiry innkeeper",
        long_description: "Garrick has run the taproom for thirty years.",
        lore: "Once a caravan guard."
      })

    conn = conn |> auth() |> get(~p"/api/npc/#{npc.id}/identity")

    assert %{
             "entity_id" => id,
             "name" => "Garrick the Innkeeper",
             "short_description" => "a wiry innkeeper",
             "long_description" => "Garrick has run the taproom for thirty years.",
             "lore" => "Once a caravan guard."
           } = json_response(conn, 200)

    assert id == npc.id
  end

  test "unknown id → 404", %{conn: conn} do
    conn = conn |> auth() |> get(~p"/api/npc/#{Ecto.UUID.generate()}/identity")
    assert json_response(conn, 404)
  end

  test "a non-UUID id → 404 (no crash)", %{conn: conn} do
    conn = conn |> auth() |> get(~p"/api/npc/not-a-uuid/identity")
    assert json_response(conn, 404)
  end
end
