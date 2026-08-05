defmodule AgenticRealmsWeb.GameLiveBehaviorsTest do
  @moduledoc """
  End-to-end LiveView tests for NPC and room behaviors.

  Structured as a single comprehensive test that exercises US1 (NPC
  greeting), US2 (NPC farewell), US3 (room narration + anti-spam), US4
  (multi-behavior composition), and US5 (multi-action composition) in
  sequence. Mirrors the other end-to-end LiveView tests.

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

    AgenticRealms.DataCase.create_character!(alice.id, name: alice.username)
    AgenticRealms.DataCase.create_character!(bob.id, name: bob.username)

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

  test "behaviors, US5 in sequence",
       %{alice_conn: alice_conn, bob_conn: bob_conn} do
    {:ok, alice_view, _html} = live(alice_conn, ~p"/play")

    # Arrival behaviors fire over PubSub, so they land after the mount
    # returns. The room narration is broadcast before the NPC greeting and
    # both reach this view in order, so waiting on the greeting means the
    # whole arrival round has been delivered.
    assert_eventually(alice_view, fn -> render(alice_view) =~ "Welcome to the Stone Atrium." end,
      label: "Alice saw Garrick's greeting",
      on_timeout: fn -> render(alice_view) end
    )

    alice_html = render(alice_view)

    assert alice_html =~ ~s(class="log-entry speech speech-npc"),
           "Alice should see Garrick's :npc_speech entry rendered with speech-npc class"

    assert alice_html =~ ~s(<span class="who">Garrick the Innkeeper</span>),
           "Garrick's display name should appear with attribution"

    assert alice_html =~ "Welcome to the Stone Atrium.",
           "Garrick's greeting text should appear in Alice's log"

    refute alice_html =~ ~r/Garrick the Innkeeper#[0-9a-f]/,
           "player-facing HTML must not contain the <name>#<id> debug identity"

    assert alice_html =~ ~s(class="log-entry narrate narrate-room"),
           "Alice should see the Stone Atrium's room narration rendered with narrate-room class"

    assert alice_html =~ "The cool air carries the scent of rain.",
           "the atrium's atmospheric narration should appear in Alice's log"

    assert alice_html =~
             ~s(<div class="log-entry narrate narrate-room">\n  The cool air carries the scent of rain.\n</div>) or
             alice_html =~
               ~s(<div class="log-entry narrate narrate-room">The cool air carries the scent of rain.</div>),
           ":room_speech must render without 'X says' attribution and without quotation marks"

    room_pos = newest_pos(alice_html, "narrate-room")
    npc_pos = newest_pos(alice_html, "speech-npc")

    assert room_pos > npc_pos,
           "FR-008a: room narration (DOM @#{room_pos}) must appear visually BEFORE " <>
             "NPC speech (DOM @#{npc_pos}); log is column-reverse so visually-earlier = higher byte offset"

    alice_room_speech_count_before = count_occurrences(alice_html, "narrate-room")
    alice_npc_speech_count_before = count_occurrences(alice_html, "speech-npc")

    {:ok, bob_view, _html} = live(bob_conn, ~p"/play")

    assert_eventually(
      bob_view,
      fn -> render(bob_view) =~ "The cool air carries the scent of rain." end,
      label: "Bob saw the room narration",
      on_timeout: fn -> render(bob_view) end
    )

    # Garrick's greeting for Bob is the one entry Alice IS meant to get from
    # Bob's arrival, so it doubles as proof that the arrival round reached
    # her. Without waiting for it the anti-spam count below would pass just
    # by being read before anything showed up.
    assert_eventually(
      alice_view,
      fn ->
        count_occurrences(render(alice_view), "speech-npc") > alice_npc_speech_count_before
      end,
      label: "Alice saw Garrick greet Bob",
      on_timeout: fn -> render(alice_view) end
    )

    bob_html = render(bob_view)

    assert bob_html =~ "The cool air carries the scent of rain.",
           "Bob (arriving player) MUST see the room narration"

    alice_html_after_bob = render(alice_view)
    alice_room_speech_count_after = count_occurrences(alice_html_after_bob, "narrate-room")

    assert alice_room_speech_count_after == alice_room_speech_count_before,
           "anti-spam: Alice (bystander) MUST NOT receive a new room narration when Bob arrives — " <>
             "expected #{alice_room_speech_count_before}, got #{alice_room_speech_count_after}"

    assert alice_html_after_bob =~ ~s(<span class="who">Garrick the Innkeeper</span>),
           "Alice (bystander) DOES see Garrick's :npc_speech for Bob's arrival"

    alice_view
    |> form("form[phx-submit='submit_command']", %{"text" => "go north"})
    |> render_submit()

    # Alice is the leaver, so her farewell came back inline from
    # render_submit. Bob is a bystander and gets his over PubSub.
    assert_eventually(bob_view, fn -> render(bob_view) =~ "Farewell, traveler." end,
      label: "Bob saw the farewell",
      on_timeout: fn -> render(bob_view) end
    )

    alice_html_after_move = render(alice_view)

    assert alice_html_after_move =~ "Farewell, traveler.",
           "Alice (leaving player) MUST receive Garrick's farewell"

    bob_html_after_move = render(bob_view)

    assert bob_html_after_move =~ "Farewell, traveler.",
           "Bob (still in the Atrium) MUST also receive Garrick's farewell — :npc_speech reaches " <>
             "all players in the speaker's room"

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

    assert_eventually(
      alice_view,
      fn -> render(alice_view) =~ "Mind the loose flagstone by the door." end,
      label: "Alice saw the second player_entered behavior",
      on_timeout: fn -> render(alice_view) end
    )

    alice_html_multi_behavior = render(alice_view)

    assert alice_html_multi_behavior =~ "Welcome to the Stone Atrium.",
           "first player_entered behavior should fire"

    assert alice_html_multi_behavior =~ "Mind the loose flagstone by the door.",
           "second player_entered behavior should fire"

    welcome_pos = newest_pos(alice_html_multi_behavior, "Welcome to the Stone Atrium.")
    flagstone_pos = newest_pos(alice_html_multi_behavior, "Mind the loose flagstone")

    assert welcome_pos > flagstone_pos,
           "multi-behavior ordering: 'Welcome' should fire before 'Mind the loose flagstone' " <>
             "(welcome DOM @#{welcome_pos} vs flagstone DOM @#{flagstone_pos}; log is column-reverse)"

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

    # Garrick only has a player_entered behavior now, so stepping out fires
    # nothing to wait for, and the mover's own room assigns are updated
    # inline by the time render_submit returns.
    alice_view
    |> form("form[phx-submit='submit_command']", %{"text" => "go north"})
    |> render_submit()

    alice_view
    |> form("form[phx-submit='submit_command']", %{"text" => "go south"})
    |> render_submit()

    assert_eventually(alice_view, fn -> render(alice_view) =~ "BETA_LINE" end,
      label: "Alice saw the second action of the multi-action behavior",
      on_timeout: fn -> render(alice_view) end
    )

    alice_html_multi_action = render(alice_view)

    assert alice_html_multi_action =~ "ALPHA_LINE",
           "first action in multi-action behavior should fire"

    assert alice_html_multi_action =~ "BETA_LINE",
           "second action in multi-action behavior should fire"

    alpha_pos = newest_pos(alice_html_multi_action, "ALPHA_LINE")
    beta_pos = newest_pos(alice_html_multi_action, "BETA_LINE")

    assert alpha_pos > beta_pos,
           "multi-action ordering: ALPHA should fire before BETA " <>
             "(alpha DOM @#{alpha_pos} vs beta DOM @#{beta_pos}; log is column-reverse)"
  end

  defp count_occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end

  defp newest_pos(haystack, needle) do
    case :binary.match(haystack, needle) do
      {pos, _len} -> pos
      :nomatch -> flunk("newest_pos: #{inspect(needle)} not found in HTML")
    end
  end
end
