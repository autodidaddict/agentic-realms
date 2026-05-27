defmodule AgenticRealmsWeb.GameLiveNPCTest do
  @moduledoc """
  End-to-end LiveView tests for feature 007 (static NPCs).

  Structured as a single comprehensive test that exercises US1 (room view
  "Also here" section), US2 (examine NPC), US3 (arrival witness via
  runtime SpawnNPC dispatch), and US4 (take refusal) in sequence. This
  mirrors the 004 / 005 / 006 LiveView pattern: multiple per-test
  setups conflict with the in-memory event store accumulating state.

  Tagged `:integration` and excluded from the default `mix test` run.
  Run with:

      mix test --include integration \\
        test/agenticrealms_web/live/game_live_npc_test.exs
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.Commands, as: WorldCommands
  alias AgenticRealms.World.Commands.CreateNPCBlueprint
  alias AgenticRealms.World.{Queries, Seed}
  alias AgenticRealms.World.Schemas.{NPCBlueprint, NPCClone}

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    Req.Test.set_req_test_to_shared(%{})

    suffix = System.unique_integer([:positive])

    {:ok, alice} =
      Accounts.register_player(%{username: "alice_n_#{suffix}", password: "pw12345678"})

    {:ok, bob} =
      Accounts.register_player(%{username: "bob_n_#{suffix}", password: "pw12345678"})

    {:ok, _} = WorldCommands.spawn(alice.id, Seed.starting_room_id())
    {:ok, _} = WorldCommands.spawn(bob.id, Seed.starting_room_id())

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

  test "static NPCs — US1, US2, US3, US4 in sequence",
       %{alice_conn: alice_conn, bob_conn: bob_conn, alice: alice, bob: bob} do
    # Foundational sanity (covers SC-002 from feature 008 + projection
    # smoke). After Seed.run/0, the blueprint exists and one clone with
    # serial 1 lives in the starting room.
    assert [%NPCBlueprint{id: "garrick_the_innkeeper", is_synthetic: false}] =
             Repo.all(NPCBlueprint)

    assert [
             %NPCClone{
               name: "Garrick the Innkeeper",
               blueprint_id: "garrick_the_innkeeper",
               serial: 1,
               room_id: room_id
             }
           ] = Repo.all(NPCClone)

    assert room_id == Seed.starting_room_id()

    # ── Feature 008 — pre-dispatch wrapper coverage (SC-008) ──────────────
    # Verify the spawn_npc_clone/3 wrapper's error paths before kicking off
    # the player session. These are pure read-model checks, no LiveView state
    # involved.

    # Unknown blueprint:
    assert {:error, :blueprint_not_found} =
             WorldCommands.spawn_npc_clone(
               "nonexistent_blueprint",
               Seed.starting_room_id(),
               Ecto.UUID.generate()
             )

    # Unknown room:
    :ok =
      WorldApp.dispatch(
        %CreateNPCBlueprint{
          blueprint_id: "test_bp_no_room",
          name: "Test NPC No Room",
          short_description: "a test npc",
          long_description: "A long description."
        },
        consistency: :strong
      )

    assert {:error, :room_not_found} =
             WorldCommands.spawn_npc_clone(
               "test_bp_no_room",
               Ecto.UUID.generate(),
               Ecto.UUID.generate()
             )

    # Name collision (Garrick is already in the starting room from seed):
    :ok =
      WorldApp.dispatch(
        %CreateNPCBlueprint{
          blueprint_id: "duplicate_garrick",
          name: "Garrick the Innkeeper",
          short_description: "another wiry innkeeper",
          long_description: "Yet another wiry man in an apron."
        },
        consistency: :strong
      )

    assert {:error, :clone_name_taken_in_room} =
             WorldCommands.spawn_npc_clone(
               "duplicate_garrick",
               Seed.starting_room_id(),
               Ecto.UUID.generate()
             )

    # Same display name in a DIFFERENT room is allowed (preserves the per-
    # room scope of FR-015):
    corridor_id = "00000000-0000-4000-8000-000000000002"

    assert {:ok, %{serial: 1}} =
             WorldCommands.spawn_npc_clone(
               "duplicate_garrick",
               corridor_id,
               Ecto.UUID.generate()
             )

    # Two spawns from the same blueprint into different rooms produce
    # consecutive serials (SC-004):
    library_id = "00000000-0000-4000-8000-000000000003"

    assert {:ok, %{serial: 2}} =
             WorldCommands.spawn_npc_clone(
               "duplicate_garrick",
               library_id,
               Ecto.UUID.generate()
             )

    # Clean up: remove the test fixtures we just added so the rest of the
    # test (US1 / US2 / US3 / US4 player flows) sees only the seeded world.
    # Otherwise, the duplicate Garricks in corridor/library would interfere
    # with the Also-here uniqueness assertions below.
    Repo.delete_all(from(c in NPCClone, where: c.blueprint_id == "duplicate_garrick"))

    # ── Feature 008 US3 — full-copy semantics (SC-003) ────────────────────
    # Mutate the seeded Garrick blueprint directly via Repo.update_all, then
    # verify the existing clone's data is unchanged.
    [garrick_clone] =
      Repo.all(from(c in NPCClone, where: c.blueprint_id == "garrick_the_innkeeper"))

    original_long_description = garrick_clone.long_description
    assert original_long_description =~ "wiry man in a stained apron"

    {1, _} =
      Repo.update_all(
        from(b in NPCBlueprint, where: b.id == "garrick_the_innkeeper"),
        set: [long_description: "MUTATED — should not appear on existing clones."]
      )

    # Blueprint changed.
    assert Repo.get(NPCBlueprint, "garrick_the_innkeeper").long_description ==
             "MUTATED — should not appear on existing clones."

    # Clone unchanged.
    refreshed_clone = Repo.get(NPCClone, garrick_clone.id)

    assert refreshed_clone.long_description == original_long_description,
           "full-copy: existing clone data MUST NOT change when the blueprint is edited (SC-003)"

    # Restore blueprint so subsequent assertions about Garrick's text still
    # match. Existing clone is already unchanged; this restoration is
    # purely cosmetic.
    {1, _} =
      Repo.update_all(
        from(b in NPCBlueprint, where: b.id == "garrick_the_innkeeper"),
        set: [long_description: original_long_description]
      )

    {:ok, alice_view, _html} = live(alice_conn, ~p"/play")
    {:ok, bob_view, _html} = live(bob_conn, ~p"/play")
    flush(alice_view)
    flush(bob_view)

    # Let presence settle.
    Process.sleep(80)
    flush(alice_view)
    flush(bob_view)

    # ── US1: room view shows "Also here" with Garrick ─────────────────────
    html = render(alice_view)

    assert html =~ ~s(class="room-section also-here"),
           "the Also here section should render in the Stone Atrium"

    assert html =~ ~s(class="room-section-label">Also here:</span>),
           "the section label MUST be the literal string 'Also here:' (FR-004)"

    assert html =~ "Garrick the Innkeeper",
           "Garrick's display name should appear in the Also here section"

    assert html =~ "wiry innkeeper",
           "Garrick's short description should appear inline with the name"

    # US1 acceptance scenario 3: moving to a room with zero NPCs renders no
    # new Also here section. We assert by counting the section across moves —
    # the corridor entry should not add to the count.
    also_here_count_before = count_occurrences(render(alice_view), "Also here:")

    submit(alice_view, "n")
    flush(alice_view)

    also_here_count_corridor = count_occurrences(render(alice_view), "Also here:")

    assert also_here_count_corridor == also_here_count_before,
           "moving to a room with zero NPCs must not add a new Also here section"

    # Back to the Atrium.
    submit(alice_view, "s")
    flush(alice_view)

    # And returning to the Atrium re-renders the section.
    also_here_count_after = count_occurrences(render(alice_view), "Also here:")

    assert also_here_count_after > also_here_count_corridor,
           "returning to the Atrium should re-render the Also here section"

    # ── US2: examine an NPC via the canonical fast path ───────────────────
    log_count_before = log_count(bob_view)

    submit(alice_view, "look garrick")
    flush(alice_view)
    Process.sleep(50)
    flush(bob_view)

    html = render(alice_view)

    assert html =~ ~s(class="log-entry detail detail-npc"),
           "the NPC detail entry should render with detail-npc class"

    assert html =~ ~s(class="detail-name">Garrick the Innkeeper</span>),
           "the NPC's display name should appear in detail-name"

    assert html =~ "wiry man in a stained apron",
           "the NPC's long description should appear in detail-body"

    # Feature 008 FR-011 / SC-006: the `<name>#<serial>` debug identity MUST
    # NOT leak into any player-facing surface.
    refute html =~ ~r/Garrick the Innkeeper#\d+/,
           "FR-011: player-facing HTML must not contain the <name>#<serial> debug identity"

    # SC-005: Bob sees no log entry from Alice's examine.
    assert log_count(bob_view) == log_count_before,
           "examining an NPC must not append a witness entry to other players"

    # Cross-room examine refusal is covered by the Examine unit test
    # "NPC in another room is not findable"; we skip the LiveView-level
    # subcheck here because it would require stubbing the LLM fallback
    # (the fast path falls through to the resolver on :no_such_target).

    # ── US3: NPC arrival witness fires live to both sessions ──────────────
    alice_count_before = log_count(alice_view)
    bob_count_before = log_count(bob_view)

    :ok =
      WorldApp.dispatch(
        %CreateNPCBlueprint{
          blueprint_id: "maelyn_the_bard",
          name: "Maelyn the Bard",
          short_description: "a slender bard tuning a lute",
          long_description:
            "A slender woman in travelling leathers, her long fingers coaxing a half-melody from a battered lute."
        },
        consistency: :strong
      )

    {:ok, _} =
      WorldCommands.spawn_npc_clone(
        "maelyn_the_bard",
        Seed.starting_room_id(),
        Ecto.UUID.generate()
      )

    # Give the broadcaster + LiveView a moment to process.
    Process.sleep(80)
    flush(alice_view)
    flush(bob_view)

    alice_html = render(alice_view)
    bob_html = render(bob_view)

    assert alice_html =~ "Maelyn the Bard arrives.",
           "Alice should receive the NPC arrival entry"

    assert bob_html =~ "Maelyn the Bard arrives.",
           "Bob (in the same room) should also receive the NPC arrival entry"

    assert log_count(alice_view) > alice_count_before
    assert log_count(bob_view) > bob_count_before

    # FR-012: the arrival entry uses the directionless form (no "from the X").
    refute alice_html =~ "Maelyn the Bard arrives from",
           "the NPC arrival entry must NOT include 'from the X' (FR-012)"

    # Subsequent room view should list both NPCs in the Also here section.
    submit(alice_view, "look")
    flush(alice_view)

    html = render(alice_view)

    assert html =~ "Garrick the Innkeeper"
    assert html =~ "Maelyn the Bard"

    # ── US3 — zero-recipient spawn (FR-013) ───────────────────────────────
    # Place an NPC in a room neither Alice nor Bob is in (the corridor).
    # Both Alice and Bob are currently in the Atrium. The corridor's room
    # topic has no subscribers; the dispatch should succeed but no log
    # entry should appear on either Alice or Bob.
    alice_count_silent = log_count(alice_view)
    bob_count_silent = log_count(bob_view)

    :ok =
      WorldApp.dispatch(
        %CreateNPCBlueprint{
          blueprint_id: "renn_the_apprentice",
          name: "Renn the Apprentice",
          short_description: "a fidgeting apprentice",
          long_description: "A nervous-looking youth in oversized robes."
        },
        consistency: :strong
      )

    {:ok, _} =
      WorldCommands.spawn_npc_clone(
        "renn_the_apprentice",
        corridor_room_id(),
        Ecto.UUID.generate()
      )

    Process.sleep(80)
    flush(alice_view)
    flush(bob_view)

    assert log_count(alice_view) == alice_count_silent,
           "Alice (not in the corridor) must not receive the arrival entry"

    assert log_count(bob_view) == bob_count_silent,
           "Bob (not in the corridor) must not receive the arrival entry"

    # But the world state reflects the spawn — going north shows Renn.
    submit(alice_view, "n")
    flush(alice_view)

    html = render(alice_view)

    assert html =~ "Renn the Apprentice",
           "the NPC spawned silently into the corridor should be visible on look"

    # Back to the Atrium for US4.
    submit(alice_view, "s")
    flush(alice_view)

    # ── US4: take refusal for an NPC ──────────────────────────────────────
    bob_count_before = log_count(bob_view)
    inventory_before = Queries.list_inventory(alice.id)

    # Use the NPC's full display name — the fast parser requires an exact
    # name match (consistent with object take resolution). A partial name
    # like "garrick" would fall through to the LLM resolver (which would
    # need to be stubbed). Refusal is the same shape either way.
    submit(alice_view, "take Garrick the Innkeeper")
    flush(alice_view)
    Process.sleep(50)
    flush(bob_view)

    html = render(alice_view)

    # HEEx auto-escapes the apostrophe (' → &#39;)
    assert html =~ "You can&#39;t take that." or html =~ "You can't take that.",
           "taking an NPC should produce the same refusal as taking a fixed object (FR-015)"

    # FR-016: world state unchanged.
    assert Queries.list_inventory(alice.id) == inventory_before,
           "the inventory must not change after a failed take"

    # FR-016: no witness entry to Bob.
    assert log_count(bob_view) == bob_count_before,
           "a failed take must not emit a witness entry to other players"

    # Garrick is still listed in the room view.
    submit(alice_view, "look")
    flush(alice_view)

    html = render(alice_view)
    assert html =~ "Garrick the Innkeeper"

    # Sanity: prove `take` of an actual takeable object still works (regression).
    submit(alice_view, "take brass lantern")
    flush(alice_view)

    html = render(alice_view)
    assert html =~ "You take the brass lantern."

    _ = alice
    _ = bob
  end

  # --- Helpers ------------------------------------------------------------

  defp corridor_room_id do
    # The North Corridor's seed id. Mirrors the pinned id in Seed.
    "00000000-0000-4000-8000-000000000002"
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

  defp log_count(view) do
    state = :sys.get_state(view.pid)
    length(state.socket.assigns.log)
  end

  defp count_occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end
end
