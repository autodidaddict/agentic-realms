defmodule AgenticRealmsWeb.NpcServiceAuthTest do
  @moduledoc "Feature 018 — shared-secret auth across all contract routes + rotation."
  use AgenticRealmsWeb.ConnCase, async: false

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Schemas.NPCClone

  @secret "test-npc-secret"

  setup do
    npc =
      Repo.insert!(%NPCClone{
        id: Ecto.UUID.generate(),
        name: "X",
        short_description: "s",
        long_description: "l",
        lore: ""
      })

    %{npc: npc}
  end

  defp req(token, path) do
    conn = build_conn() |> Plug.Conn.put_req_header("accept", "application/json")

    conn =
      if token,
        do: Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token),
        else: conn

    get(conn, path)
  end

  test "every route rejects a missing token with 401", %{npc: npc} do
    for path <- [~p"/api/npc/#{npc.id}/identity", ~p"/api/npc/#{npc.id}/surroundings"] do
      assert json_response(req(nil, path), 401)
    end
  end

  test "every route rejects a wrong token with 401", %{npc: npc} do
    for path <- [~p"/api/npc/#{npc.id}/identity", ~p"/api/npc/#{npc.id}/surroundings"] do
      assert json_response(req("wrong", path), 401)
    end
  end

  test "the correct token is honored", %{npc: npc} do
    assert json_response(req(@secret, ~p"/api/npc/#{npc.id}/identity"), 200)
  end

  test "rotating the secret rejects the old value and honors the new", %{npc: npc} do
    original = Application.get_env(:agenticrealms, AgenticRealms.NpcMinds)

    Application.put_env(
      :agenticrealms,
      AgenticRealms.NpcMinds,
      Keyword.put(original, :service_secret, "rotated-secret")
    )

    on_exit(fn -> Application.put_env(:agenticrealms, AgenticRealms.NpcMinds, original) end)

    assert json_response(req(@secret, ~p"/api/npc/#{npc.id}/identity"), 401)
    assert json_response(req("rotated-secret", ~p"/api/npc/#{npc.id}/identity"), 200)
  end
end
