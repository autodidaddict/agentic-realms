defmodule AgenticRealmsWeb.GameLivePresenceTest do
  @moduledoc """
  End-to-end test that the Present HUD card updates on a witness's LiveView
  when another player arrives or departs.

  Reproduces the user-reported bug: alice in atrium, kevin moves in/out,
  alice's Present HUD should refresh to match.
  """

  use AgenticRealmsWeb.ConnCase, async: false

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

    %{alice: alice, kevin: kevin, alice_conn: alice_conn}
  end

  test "alice's Present HUD updates when kevin moves out of and back into the atrium",
       %{alice_conn: conn, kevin: kevin} do
    {:ok, view, _html} = live(conn, ~p"/play")

    # Give the LiveView a beat to finish post-mount setup (PubSub
    # subscriptions complete inside mount but the test process can race
    # against the broadcast otherwise).
    Process.sleep(50)
    _ = :sys.get_state(view.pid)

    initial_count = count_presence_rows(view)

    assert initial_count == 1,
           "expected 1 present row initially. HUD section: " <> present_section(view)

    {:ok, _} = Commands.move(kevin.id, :east)
    assert_eventually(fn -> count_presence_rows(view) == 0 end, view)

    {:ok, _} = Commands.move(kevin.id, :west)
    assert_eventually(fn -> count_presence_rows(view) == 1 end, view)
  end

  # Polls a predicate against the rendered LiveView until it returns true or
  # times out. Forces flushes via :sys.get_state on the LiveView process so
  # any pending handle_info events are processed before each check.
  defp assert_eventually(check, view, timeout_ms \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_assert_eventually(check, view, deadline)
  end

  defp do_assert_eventually(check, view, deadline) do
    _ = :sys.get_state(view.pid)

    if check.() do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        state = :sys.get_state(view.pid)

        flunk(
          "predicate did not become true within timeout.\n" <>
            "socket :presence = " <>
            inspect(state.socket.assigns[:presence]) <>
            "\nPresent HUD section: " <>
            present_section(view)
        )
      else
        Process.sleep(20)
        do_assert_eventually(check, view, deadline)
      end
    end
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
