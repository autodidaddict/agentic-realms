defmodule AgenticRealmsWeb.Plugs.RequireServiceTokenTest do
  @moduledoc "The shared-secret bearer auth plug."
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias AgenticRealmsWeb.Plugs.RequireServiceToken

  @secret "test-npc-secret"

  defp call(headers) do
    conn =
      Enum.reduce(headers, conn(:get, "/api/npc/x/identity"), fn {k, v}, c ->
        put_req_header(c, k, v)
      end)

    RequireServiceToken.call(conn, RequireServiceToken.init([]))
  end

  test "correct token passes through un-halted" do
    conn = call([{"authorization", "Bearer #{@secret}"}])
    refute conn.halted
  end

  test "missing token → 401 and halts before the action" do
    conn = call([])
    assert conn.halted
    assert conn.status == 401
  end

  test "wrong token → 401 and halts" do
    conn = call([{"authorization", "Bearer wrong-token"}])
    assert conn.halted
    assert conn.status == 401
  end

  test "fails closed when the secret is unset" do
    original = Application.get_env(:agenticrealms, AgenticRealms.NpcMinds)

    Application.put_env(
      :agenticrealms,
      AgenticRealms.NpcMinds,
      Keyword.put(original, :service_secret, nil)
    )

    on_exit(fn -> Application.put_env(:agenticrealms, AgenticRealms.NpcMinds, original) end)

    conn = call([{"authorization", "Bearer #{@secret}"}])
    assert conn.halted
    assert conn.status == 401
  end
end
