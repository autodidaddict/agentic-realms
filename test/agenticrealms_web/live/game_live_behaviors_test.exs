defmodule AgenticRealmsWeb.GameLiveBehaviorsTest do
  @moduledoc """
  End-to-end LiveView tests for feature 009 (NPC and room behaviors).

  Structured as a single comprehensive test that exercises US1 (NPC
  greeting), US2 (NPC farewell), US3 (room narration + anti-spam), US4
  (multi-behavior composition), and US5 (multi-action composition) in
  sequence. Mirrors the feature 007 / 008 LiveView pattern.

  Tagged `:integration` and excluded from the default `mix test` run.
  Run with:

      mix test --include integration \\
        test/agenticrealms_web/live/game_live_behaviors_test.exs
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.{Queries, Seed}
  alias AgenticRealms.World.Schemas.NPCClone

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    Req.Test.set_req_test_to_shared(%{})

    suffix = System.unique_integer([:positive])

    {:ok, alice} =
      Accounts.register_player(%{username: "alice_b_#{suffix}", password: "pw12345678"})

    {:ok, bob} =
      Accounts.register_player(%{username: "bob_b_#{suffix}", password: "pw12345678"})

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

  test "behaviors — US1, US2, US3, US4, US5 in sequence",
       %{alice_conn: alice_conn, bob_conn: bob_conn} do
    # ── US1: NPC greets a player who arrives in the room ──────────────────
    # Alice logs in. The GameLive mount dispatches SpawnPlayer with
    # consistency: :strong; the BehaviorsInterpreter handles PlayerSpawned
    # and broadcasts BehaviorUtterance entries before mount completes.
    {:ok, alice_view, _html} = live(alice_conn, ~p"/play")
    flush(alice_view)
    Process.sleep(120)
    flush(alice_view)

    alice_html = render(alice_view)

    # Garrick says hello (NPC speech with attribution).
    assert alice_html =~ ~s(class="log-entry speech speech-npc"),
           "Alice should see Garrick's :npc_speech entry rendered with speech-npc class"

    assert alice_html =~ ~s(<span class="who">Garrick the Innkeeper</span>),
           "Garrick's display name should appear with attribution"

    assert alice_html =~ "Welcome to the Stone Atrium.",
           "Garrick's greeting text should appear in Alice's log"

    # FR-011: the LPMud-style debug identity MUST NOT appear in player-facing HTML.
    refute alice_html =~ ~r/Garrick the Innkeeper#\d+/,
           "FR-011: player-facing HTML must not contain the <name>#<serial> debug identity"

    # ── US3: Room narration on arrival (atmospheric line, no attribution) ─
    assert alice_html =~ ~s(class="log-entry narrate narrate-room"),
           "Alice should see the Stone Atrium's room narration rendered with narrate-room class"

    assert alice_html =~ "The cool air carries the scent of rain.",
           "the atrium's atmospheric narration should appear in Alice's log"

    # The room_speech entry MUST NOT contain "says" attribution or quotation marks.
    # We assert the rendered room_speech div has no <span class="who"> inside it
    # by checking the exact rendered shape.
    assert alice_html =~
             ~s(<div class="log-entry narrate narrate-room">\n  The cool air carries the scent of rain.\n</div>) or
             alice_html =~
               ~s(<div class="log-entry narrate narrate-room">The cool air carries the scent of rain.</div>),
           ":room_speech must render without 'X says' attribution and without quotation marks"

    # FR-008a: room narration MUST appear BEFORE the NPC speech in the log.
    room_pos = :binary.match(alice_html, "narrate-room") |> elem(0)
    npc_pos = :binary.match(alice_html, "speech-npc") |> elem(0)

    assert room_pos < npc_pos,
           "FR-008a: room narration (#{room_pos}) must appear BEFORE NPC speech (#{npc_pos})"

    # ── US3 anti-spam: room_speech is triggering-player-only ──────────────
    # Bob now mounts a separate session. His arrival should trigger room
    # narration FOR HIM. Alice's previous-mount-time log should NOT have
    # received another room narration from Bob's arrival.
    alice_room_speech_count_before = count_occurrences(alice_html, "narrate-room")

    {:ok, bob_view, _html} = live(bob_conn, ~p"/play")
    flush(bob_view)
    Process.sleep(120)
    flush(bob_view)
    flush(alice_view)

    bob_html = render(bob_view)

    assert bob_html =~ "The cool air carries the scent of rain.",
           "Bob (arriving player) MUST see the room narration"

    alice_html_after_bob = render(alice_view)
    alice_room_speech_count_after = count_occurrences(alice_html_after_bob, "narrate-room")

    assert alice_room_speech_count_after == alice_room_speech_count_before,
           "anti-spam: Alice (bystander) MUST NOT receive a new room narration when Bob arrives — " <>
             "expected #{alice_room_speech_count_before}, got #{alice_room_speech_count_after}"

    # But the bystander DOES see NPC speech from arrivals (feature 004 semantics).
    assert alice_html_after_bob =~ ~s(<span class="who">Garrick the Innkeeper</span>),
           "Alice (bystander) DOES see Garrick's :npc_speech for Bob's arrival"

    # ── US2: NPC farewell when a player moves out ─────────────────────────
    # Alice moves north. The behavior interpreter fires `player_left` in
    # the source room (Atrium). Garrick says farewell. The leaving player
    # MUST receive the farewell on her player-topic.
    alice_view
    |> form("form[phx-submit='submit_command']", %{"text" => "go north"})
    |> render_submit()

    flush(alice_view)
    Process.sleep(120)
    flush(alice_view)
    flush(bob_view)

    alice_html_after_move = render(alice_view)

    assert alice_html_after_move =~ "Farewell, traveler.",
           "Alice (leaving player) MUST receive Garrick's farewell"

    bob_html_after_move = render(bob_view)

    assert bob_html_after_move =~ "Farewell, traveler.",
           "Bob (still in the Atrium) MUST also receive Garrick's farewell — :npc_speech reaches " <>
             "all players in the speaker's room"

    # ── US4: Multi-behavior composition ───────────────────────────────────
    # Mutate Garrick's clone to have multiple player_entered behaviors,
    # then move Alice back into the Atrium.
    {:ok, garrick_clone_id} =
      Queries.resolve_npc_in_room(Seed.starting_room_id(), "Garrick the Innkeeper")

    {1, _} =
      Repo.update_all(
        from(c in NPCClone, where: c.id == ^garrick_clone_id),
        set: [
          behaviors: [
            %{
              "trigger" => "player_entered",
              "actions" => [%{"type" => "say", "text" => "Welcome to the Stone Atrium."}]
            },
            %{
              "trigger" => "player_entered",
              "actions" => [%{"type" => "say", "text" => "Mind the loose flagstone by the door."}]
            },
            %{
              "trigger" => "player_left",
              "actions" => [%{"type" => "say", "text" => "Farewell, traveler."}]
            }
          ]
        ]
      )

    alice_view
    |> form("form[phx-submit='submit_command']", %{"text" => "go south"})
    |> render_submit()

    flush(alice_view)
    Process.sleep(120)
    flush(alice_view)

    alice_html_multi_behavior = render(alice_view)

    assert alice_html_multi_behavior =~ "Welcome to the Stone Atrium.",
           "first player_entered behavior should fire"

    assert alice_html_multi_behavior =~ "Mind the loose flagstone by the door.",
           "second player_entered behavior should fire"

    welcome_pos = find_last_occurrence(alice_html_multi_behavior, "Welcome to the Stone Atrium.")
    flagstone_pos = find_last_occurrence(alice_html_multi_behavior, "Mind the loose flagstone")

    assert welcome_pos < flagstone_pos,
           "multi-behavior ordering: 'Welcome' should appear before 'Mind the loose flagstone' " <>
             "(positions #{welcome_pos} vs #{flagstone_pos})"

    # ── US5: Multi-action composition (single behavior, multiple actions) ─
    {1, _} =
      Repo.update_all(
        from(c in NPCClone, where: c.id == ^garrick_clone_id),
        set: [
          behaviors: [
            %{
              "trigger" => "player_entered",
              "actions" => [
                %{"type" => "say", "text" => "ALPHA_LINE"},
                %{"type" => "say", "text" => "BETA_LINE"}
              ]
            }
          ]
        ]
      )

    # Alice moves out and back in once more to trigger the new behavior.
    alice_view
    |> form("form[phx-submit='submit_command']", %{"text" => "go north"})
    |> render_submit()

    flush(alice_view)
    Process.sleep(120)
    flush(alice_view)

    alice_view
    |> form("form[phx-submit='submit_command']", %{"text" => "go south"})
    |> render_submit()

    flush(alice_view)
    Process.sleep(120)
    flush(alice_view)

    alice_html_multi_action = render(alice_view)

    assert alice_html_multi_action =~ "ALPHA_LINE",
           "first action in multi-action behavior should fire"

    assert alice_html_multi_action =~ "BETA_LINE",
           "second action in multi-action behavior should fire"

    alpha_pos = find_last_occurrence(alice_html_multi_action, "ALPHA_LINE")
    beta_pos = find_last_occurrence(alice_html_multi_action, "BETA_LINE")

    assert alpha_pos < beta_pos,
           "multi-action ordering: ALPHA before BETA (positions #{alpha_pos} vs #{beta_pos})"
  end

  # --- Helpers ------------------------------------------------------------

  defp flush(view) do
    _ = :sys.get_state(view.pid)
    :ok
  end

  defp count_occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end

  defp find_last_occurrence(haystack, needle) do
    # Returns the byte position of the last occurrence of `needle` in
    # `haystack`. Used for ordering assertions across multiple lines that
    # may also appear earlier in the log (e.g., from previous moves).
    haystack
    |> String.split(needle)
    |> Enum.drop(-1)
    |> Enum.map(&byte_size/1)
    |> Enum.sum()
    |> Kernel.+(byte_size(needle) * (length(String.split(haystack, needle)) - 2))
  end
end
