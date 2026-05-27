defmodule AgenticRealmsWeb.GameLiveExamineTest do
  @moduledoc """
  End-to-end LiveView tests for feature 006 (examine objects and players).

  Structured as a single comprehensive test that exercises US1 (room object),
  US2 (inventory object), and US3 (player + self + privacy) in sequence — one
  `Seed.run` setup, one (or two, for the multi-session player examine) mounted
  LiveViews. This mirrors the 004 / 005 LiveView test pattern: multiple
  per-test setups conflict with the in-memory event store accumulating state.

  Tagged `:integration` and excluded from the default `mix test` run. Run with:

      mix test --include integration \\
        test/agenticrealms_web/live/game_live_examine_test.exs
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.{Commands, Queries, Seed}

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    Req.Test.set_req_test_to_shared(%{})

    suffix = System.unique_integer([:positive])

    {:ok, alice} =
      Accounts.register_player(%{username: "alice_e_#{suffix}", password: "pw12345678"})

    {:ok, bob} = Accounts.register_player(%{username: "bob_e_#{suffix}", password: "pw12345678"})

    {:ok, _} = Commands.spawn(alice.id, Seed.starting_room_id())
    {:ok, _} = Commands.spawn(bob.id, Seed.starting_room_id())

    alice_conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, alice.id)

    bob_conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, bob.id)

    %{alice: alice, bob: bob, alice_conn: alice_conn, bob_conn: bob_conn}
  end

  test "examine objects and players — US1, US2, US3 in sequence",
       %{alice_conn: alice_conn, bob_conn: bob_conn, alice: alice, bob: bob} do
    {:ok, alice_view, _html} = live(alice_conn, ~p"/play")
    {:ok, bob_view, _html} = live(bob_conn, ~p"/play")
    flush(alice_view)
    flush(bob_view)

    lantern_name = first_object_name(alice.id)

    # Give presence broadcasts time to settle on both views before any examine
    Process.sleep(80)
    flush(alice_view)
    flush(bob_view)

    # ── US1: examine a room object via the fast path ──────────────────────
    log_count_before = bob_log_count(bob_view)

    submit(alice_view, "look #{lantern_name}")
    flush(alice_view)
    Process.sleep(50)
    flush(bob_view)

    html = render(alice_view)

    assert html =~ ~s(class="log-entry detail detail-object"),
           "the detail entry should render with detail-object class"

    assert html =~ ~s(class="detail-name">#{lantern_name}</span>),
           "the object's name should appear in detail-name"

    # The seed's brass lantern long description includes "dented brass".
    assert html =~ "dented brass",
           "the object's long description should appear in detail-body"

    # The lantern is still in the room (examine is read-only).
    assert lantern_name in Enum.map(
             Queries.look_room(alice.id) |> elem(1) |> Map.get(:objects),
             & &1.name
           )

    # SC-005 — Bob (in the same room) sees NO new log entry from Alice's examine.
    flush(bob_view)

    assert bob_log_count(bob_view) == log_count_before,
           "examining must not append a witness entry to other players in the room"

    # ── US1 via LLM fallback (natural-language examine) ───────────────────
    stub_look_target(lantern_name)

    submit(alice_view, "examine the #{lantern_name}")
    await_unlock(alice_view)

    html = render(alice_view)
    # The :cmd echo shows the literal natural-language input
    assert html =~ ~s(class="log-entry cmd">examine the #{lantern_name}</div>),
           "the literal natural-language input should be echoed verbatim"

    # And another :detail entry is appended (we now have two)
    detail_count = html |> String.split(~s(class="log-entry detail detail-object")) |> length()
    assert detail_count >= 3, "expected at least two detail-object entries by now"

    # ── US2: examine an inventory object after taking it ──────────────────
    submit(alice_view, "take #{lantern_name}")
    flush(alice_view)

    # Move to the corridor — no lantern there
    submit(alice_view, "n")
    flush(alice_view)

    # Confirm the lantern is in Alice's inventory and not in the corridor's objects
    assert lantern_name in Enum.map(Queries.list_inventory(alice.id), & &1.name)

    submit(alice_view, "look #{lantern_name}")
    flush(alice_view)

    html = render(alice_view)

    assert html =~ ~s(class="detail-name">#{lantern_name}</span>),
           "examining a carried object should render the detail entry"

    assert html =~ "dented brass",
           "the long description should be visible (sourced from inventory copy)"

    # ── US2 via LLM fallback (natural-language inventory examine) ─────────
    stub_look_target(lantern_name)

    submit(alice_view, "read my #{lantern_name} closely")
    await_unlock(alice_view)

    html = render(alice_view)
    assert html =~ ~s(class="log-entry cmd">read my #{lantern_name} closely</div>)

    # ── US3: examine another player (in the corridor — first bring Bob there) ─
    # Bring Alice back to the atrium where Bob is
    submit(alice_view, "s")
    flush(alice_view)

    log_count_before = bob_log_count(bob_view)
    submit(alice_view, "look #{bob.username}")
    flush(alice_view)

    html = render(alice_view)

    assert html =~ ~s(class="log-entry detail detail-player"),
           "the player detail entry should render with detail-player class"

    assert html =~ "#{bob.username}</span> is a player.",
           "the placeholder body should be '<name> is a player.'"

    # Privacy: Bob's log is unchanged
    flush(bob_view)

    assert bob_log_count(bob_view) == log_count_before,
           "examining a player must not append a witness entry to that player"

    # US3 — self-examine via 'me'
    submit(alice_view, "look me")
    flush(alice_view)

    html = render(alice_view)

    assert html =~ "#{alice.username}</span> is a player.",
           "self-examination via 'me' should render the acting player's name"

    # US3 — self-examine via 'self'
    submit(alice_view, "look self")
    flush(alice_view)
    html = render(alice_view)

    # Two distinct entries with the acting player's name now exist.
    self_count =
      html
      |> String.split(~s(class="detail-name">#{alice.username}</span> is a player.))
      |> length()
      |> Kernel.-(1)

    assert self_count >= 2, "expected at least two self-examine detail entries"

    # ── US3 — natural-language player examine via LLM fallback ────────────
    stub_look_target(bob.username)

    submit(alice_view, "who is #{bob.username} anyway")
    await_unlock(alice_view)

    html = render(alice_view)
    assert html =~ ~s(class="log-entry cmd">who is #{bob.username} anyway</div>)
    assert html =~ "#{bob.username}</span> is a player."

    # ── US3 — refusal for a target that doesn't resolve (after fallback) ──
    # Stub the resolver to also fail to find — refuse with a refusal message.
    # (Apostrophe-free message — HEEx escapes apostrophes in rendered output.)
    stub_refuse("Ghost not seen anywhere.")

    submit(alice_view, "look ghost_phantom_zzz")
    await_unlock(alice_view)

    html = render(alice_view)
    # The fast path returns :no_such_target, fallback to LLM, LLM refuses.
    assert html =~ "Ghost not seen anywhere."
  end

  # --- Helpers ------------------------------------------------------------

  defp stub_look_target(target) do
    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "toolu_test",
            "name" => "look",
            "input" => %{"target" => target}
          }
        ],
        "stop_reason" => "tool_use"
      })
    end)
  end

  defp stub_refuse(message) do
    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "toolu_test",
            "name" => "refuse",
            "input" => %{"message" => message}
          }
        ],
        "stop_reason" => "tool_use"
      })
    end)
  end

  defp submit(view, text) do
    view
    |> form("form[phx-submit='submit_command']", %{"text" => text})
    |> render_submit()
  end

  defp flush(view) do
    _ = :sys.get_state(view.pid)
    :ok
  end

  defp await_unlock(view, timeout_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_unlock(view, deadline)
  end

  defp do_await_unlock(view, deadline) do
    state = :sys.get_state(view.pid)

    cond do
      not state.socket.assigns.input_locked ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("resolver task did not complete (input still locked) within timeout")

      true ->
        Process.sleep(25)
        do_await_unlock(view, deadline)
    end
  end

  defp bob_log_count(view) do
    state = :sys.get_state(view.pid)
    length(state.socket.assigns.log)
  end

  defp first_object_name(player_id) do
    {:ok, room} = Queries.look_room(player_id)

    case room.objects do
      [obj | _] -> obj.name
      [] -> flunk("expected the starting room to contain a takeable object")
    end
  end
end
