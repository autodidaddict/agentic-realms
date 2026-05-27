defmodule AgenticRealmsWeb.GameLivePresenceTest do
  @moduledoc """
  End-to-end test that the Present HUD card updates on a witness's LiveView
  when another player arrives or departs.

  Reproduces the user-reported bug: alice in atrium, kevin moves in/out,
  alice's Present HUD should refresh to match.
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.{Commands, Seed}

  setup %{conn: conn} do
    Seed.run()

    {:ok, alice} = Accounts.register_player(%{username: "alice_pres", password: "pw12345678"})
    {:ok, kevin} = Accounts.register_player(%{username: "kevin_pres", password: "pw12345678"})

    {:ok, _} = Commands.spawn(alice.id, Seed.starting_room_id())
    {:ok, _} = Commands.spawn(kevin.id, Seed.starting_room_id())

    alice_conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, alice.id)

    kevin_conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, kevin.id)

    %{alice: alice, kevin: kevin, alice_conn: alice_conn, kevin_conn: kevin_conn}
  end

  test "alice's Present HUD updates when kevin moves out of and back into the atrium",
       %{alice_conn: conn, kevin_conn: kconn, kevin: kevin} do
    {:ok, view, _html} = live(conn, ~p"/play")
    # Mount kevin's LiveView too so Phoenix.Presence tracks him as online.
    # Without this, the Present HUD's online-only filter (Queries.list_other_players)
    # correctly excludes him — he's spawned in the world but not connected.
    {:ok, _kevin_view, _} = live(kconn, ~p"/play")

    # Give the LiveView a beat to finish post-mount setup (PubSub
    # subscriptions complete inside mount but the test process can race
    # against the broadcast otherwise).
    Process.sleep(50)
    _ = :sys.get_state(view.pid)

    initial_count = count_presence_rows(view)

    assert initial_count == 1,
           "expected 1 present row initially. HUD section: " <> present_section(view)

    {:ok, _} = Commands.move(kevin.id, :east)

    assert_eventually(view, fn -> count_presence_rows(view) == 0 end,
      label: "presence row count == 0 after kevin moves east",
      on_timeout: fn -> present_section(view) end
    )

    {:ok, _} = Commands.move(kevin.id, :west)

    assert_eventually(view, fn -> count_presence_rows(view) == 1 end,
      label: "presence row count == 1 after kevin moves back west",
      on_timeout: fn -> present_section(view) end
    )
  end

  defp count_presence_rows(view) do
    view
    |> render()
    |> then(&Regex.scan(~r/class="presence-row"/, &1))
    |> length()
  end

  defp present_section(view) do
    html = render(view)

    case Regex.run(
           ~r/<div class="hud-card">\s*<button[^>]*>\s*<span class="title">Present.*?<\/div>\s*<\/div>/s,
           html
         ) do
      [match | _] -> String.slice(match, 0, 600)
      _ -> "(no Present hud-card matched). Full HTML head: " <> String.slice(html, 0, 400)
    end
  end
end
