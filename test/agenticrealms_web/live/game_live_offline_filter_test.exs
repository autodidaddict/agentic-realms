defmodule AgenticRealmsWeb.GameLiveOfflineFilterTest do
  @moduledoc """
  Regression test for the user-reported bug: players whose persisted
  `current_room_id` matches the viewer's room but who have zero connected
  LiveView sessions (i.e., are offline) MUST NOT appear in the Present HUD
  card nor in `look` output.

  Lives in its own file so it gets a fresh `Seed.run/0` setup invocation —
  multiple tests in one file currently conflict between the rolled-back read
  model (Ecto sandbox) and the persistent in-memory event store, which
  causes `Commands.spawn/2` to time out on the second test. Splitting
  files is the lightest workaround until the test infra learns to reset
  the event store between tests.
  """

  use AgenticRealmsWeb.ConnCase, async: false

  # Tagged :integration and excluded from default `mix test` — see the
  # equivalent note in `game_live_communication_test.exs`. In-memory event
  # store state accumulates across the suite; running this in the default
  # run would conflict with `game_live_presence_test`.
  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.{Commands, Seed}

  setup %{conn: conn} do
    # Defensive seeding for cross-file ordering — see also game_live_presence_test.
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    {:ok, alice} = Accounts.register_player(%{username: "alice_off", password: "pw12345678"})
    {:ok, kevin} = Accounts.register_player(%{username: "kevin_off", password: "pw12345678"})

    starting = Seed.starting_room_id()
    AgenticRealms.DataCase.create_character!(alice.id, name: alice.username)
    {:ok, _} = Commands.spawn(alice.id, starting)
    AgenticRealms.DataCase.create_character!(kevin.id, name: kevin.username)
    {:ok, _} = Commands.spawn(kevin.id, starting)

    alice_conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, alice.id)

    %{alice: alice, kevin: kevin, alice_conn: alice_conn}
  end

  test "offline players do not appear in the Present HUD or in look output",
       %{alice_conn: conn} do
    # Only Alice mounts a LiveView. Kevin is spawned in the atrium but has
    # zero connected sessions, so Phoenix.Presence does not track him —
    # `Queries.list_other_players/2` must filter him out.
    {:ok, view, _html} = live(conn, ~p"/play")

    # Let the mount finish; Phoenix.Presence's tracked-self join completes
    # before this returns control here.
    _ = :sys.get_state(view.pid)
    Process.sleep(50)
    _ = :sys.get_state(view.pid)

    # 1. HUD: zero "presence-row" entries (alice excludes herself; kevin is offline)
    rows =
      view
      |> render()
      |> then(&Regex.scan(~r/class="presence-row"/, &1))
      |> length()

    assert rows == 0, "expected zero present rows; kevin has no connected sessions"

    # 2. `look` output: kevin's username must not appear in the rendered room
    view
    |> form("form[phx-submit='submit_command']", %{"text" => "look"})
    |> render_submit()

    _ = :sys.get_state(view.pid)
    html = render(view)
    refute html =~ "kevin_off", "kevin should not appear in look output while offline"
  end
end
