defmodule AgenticRealmsWeb.GameLiveCommunicationTest do
  @moduledoc """
  End-to-end LiveView tests for feature 004 (player communication).

  This file is intentionally structured as a single comprehensive test
  exercising all US1 scenarios in sequence, sharing one `Seed.run`
  invocation. Multiple per-test setup invocations conflict with the
  combination of (a) Ecto sandbox rollback of the read model and (b)
  in-memory event store state that persists across tests within a run —
  Seed.run's read-model-only check decides "not seeded" on the second
  test, but the aggregates disagree.

  Per-verb unit-level behavior is covered in
  `test/agenticrealms/world/communication_test.exs`.
  """

  use AgenticRealmsWeb.ConnCase, async: false

  # Tagged :integration and excluded from the default `mix test` run because
  # this test depends on a fresh in-memory event store — when the full suite
  # runs prior aggregates accumulate state and `Commands.spawn` hits
  # `:consistency_timeout`. Run in isolation with
  #   mix test test/agenticrealms_web/live/game_live_communication_test.exs
  # or explicitly include with `mix test --include integration`.
  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.{Commands, Seed}

  setup %{conn: conn} do
    # Defensive: Seed.run's read-model count check can disagree with the
    # in-memory event store state when prior tests in the suite have already
    # seeded the aggregates. Catch the MatchError and treat as already-seeded.
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])

    {:ok, alice} =
      Accounts.register_player(%{username: "alice_#{suffix}", password: "pw12345678"})

    {:ok, bob} = Accounts.register_player(%{username: "bob_#{suffix}", password: "pw12345678"})

    {:ok, carol} =
      Accounts.register_player(%{username: "carol_#{suffix}", password: "pw12345678"})

    starting = Seed.starting_room_id()
    {:ok, _} = Commands.spawn(alice.id, starting)
    {:ok, _} = Commands.spawn(bob.id, starting)
    {:ok, _} = Commands.spawn(carol.id, starting)

    %{
      alice: alice,
      bob: bob,
      carol: carol,
      alice_conn: conn_for(conn, alice.id),
      bob_conn: conn_for(conn, bob.id),
      carol_conn: conn_for(conn, carol.id)
    }
  end

  test "US1 say: full scenario sweep — witness, actor confirmation, multi-session, escape, refusals",
       %{alice_conn: ac, bob_conn: bc, carol_conn: cc, carol: carol} do
    # Move Carol to a different room before mounting any LiveView so the
    # cross-room assertions can use her as the "different room" witness.
    {:ok, _} = Commands.move(carol.id, :east)

    {:ok, alice_view, _} = live(ac, ~p"/play")
    {:ok, alice_tab2, _} = live(ac, ~p"/play")
    {:ok, bob_view, _} = live(bc, ~p"/play")
    {:ok, carol_view, _} = live(cc, ~p"/play")

    flush(alice_view)
    flush(alice_tab2)
    flush(bob_view)
    flush(carol_view)

    # --- Scenario 1: Alice says hello → Bob (same room) sees witness entry
    submit(alice_view, "say hello there")
    flush(bob_view)
    flush(alice_view)
    flush(alice_tab2)
    flush(carol_view)

    bob_html = render(bob_view)
    assert bob_html =~ "alice_", "Bob's render should mention Alice's username"
    assert bob_html =~ "hello there", "Bob's render should contain Alice's spoken text"

    assert bob_html =~ ~s|class="log-entry speech"|,
           "Bob's render should have a :speech log entry"

    # --- Scenario 2: Alice's originating tab sees the actor-side confirmation
    alice_html = render(alice_view)

    assert alice_html =~ ~s|class="log-entry speech speech-self"|,
           "Alice's originating tab should show the :speech_self confirmation"

    assert alice_html =~ "hello there"

    # --- Scenario 3: Alice's OTHER tab (multi-session) sees the witness entry, not the confirmation
    alice_tab2_html = render(alice_tab2)
    assert alice_tab2_html =~ ~s|class="log-entry speech"|

    refute alice_tab2_html =~ ~s|class="log-entry speech speech-self"|,
           "Alice's tab 2 should NOT receive the actor-side confirmation"

    assert alice_tab2_html =~ "hello there"

    # --- Scenario 4: Carol (different room) sees nothing
    carol_html = render(carol_view)
    refute carol_html =~ "hello there", "Carol in a different room should NOT see Alice's say"

    # --- Scenario 5: empty say from Alice → "Say what?" refusal, no broadcast
    submit(alice_view, "say")
    flush(alice_view)
    flush(bob_view)

    assert render(alice_view) =~ "Say what?"
    # Bob should not see anything new — assert his render still doesn't contain
    # "hello there" only once (no new utterance to add).
    bob_html_after = render(bob_view)
    assert utterance_count(bob_html_after, "hello there") == 1

    # --- Scenario 6: HTML-tagged say → escaped on render
    submit(alice_view, "say <script>alert(1)</script>")
    flush(bob_view)
    bob_html_xss = render(bob_view)

    assert bob_html_xss =~ "&lt;script&gt;alert(1)&lt;/script&gt;",
           "Bob's render should contain the HTML-escaped form"

    refute Regex.match?(~r/<script[^>]*>alert\(1\)<\/script>/, bob_html_xss),
           "Bob's render must not contain an unescaped <script> element"

    # --- Scenario 7: 501-char say → "too long" refusal
    submit(alice_view, "say " <> String.duplicate("x", 501))
    flush(alice_view)
    assert render(alice_view) =~ "too long"
  end

  # --- Helpers ------------------------------------------------------------

  defp conn_for(conn, player_id) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:player_id, player_id)
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

  defp utterance_count(html, needle) do
    html
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end
end
