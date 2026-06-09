defmodule AgenticRealmsWeb.GameLiveQuestTest do
  @moduledoc """
  End-to-end LiveView + projector test for feature 013 (Quest System v1).

  Exercises US1 (accept → quest spawns + log appears), US2 (pickup updates
  progress live), US3 (finalize destroys items, mints reward, marks
  completed), plus multi-player isolation (SC-003) and sticky completion
  (FR-012) in a single sequential test. Follows the same comprehensive-
  single-test pattern as `game_live_npc_test.exs` to avoid fighting the
  shared in-memory event store across nested setups.

  Tagged `:integration` and excluded from the default `mix test` run.
  Run with:

      mix test --include integration \\
        test/agenticrealms_web/live/game_live_quest_test.exs
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Commands, as: WorldCommands
  alias AgenticRealms.World.{Queries, Quests, Seed}
  alias AgenticRealms.World.Schemas.{Object, QuestInstance}

  @blueprint_id "amaranth_the_orchard_keeper"
  @slug "golden_apples"
  @cottage_room_id "00000000-0000-4000-8000-000000000008"
  @old_grove_room_id "00000000-0000-4000-8000-000000000009"
  @wild_apple_room_id "00000000-0000-4000-8000-00000000000a"
  @forgotten_corner_room_id "00000000-0000-4000-8000-00000000000b"
  @alice_spawn_rooms [@old_grove_room_id, @wild_apple_room_id, @forgotten_corner_room_id]

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    suffix = System.unique_integer([:positive])

    {:ok, alice} =
      Accounts.register_player(%{username: "alice_q_#{suffix}", password: "pw12345678"})

    {:ok, bob} =
      Accounts.register_player(%{username: "bob_q_#{suffix}", password: "pw12345678"})

    # Spawn both players into the starting room, then teleport them to
    # the Orchard Keeper's cottage so the integration test doesn't have
    # to drive Blackmire → Hollowvale movement. We use the existing
    # MovePlayer pathway by directly dispatching, since the seed exits
    # are set up.
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

  test "quest lifecycle + multi-player isolation + sticky completion",
       %{alice: alice, bob: bob, alice_conn: alice_conn, bob_conn: _bob_conn} do
    # ── Seed sanity ────────────────────────────────────────────────────
    # The Orchard Keeper blueprint exists with the FetchQuest in its
    # catalog, and the four Hollowvale rooms were created.
    blueprint =
      Repo.get(AgenticRealms.World.Schemas.Blueprint, @blueprint_id)

    assert blueprint != nil, "Orchard Keeper blueprint should be seeded"
    assert [catalog_entry] = blueprint.quests
    assert catalog_entry["slug"] == @slug
    assert [criterion] = catalog_entry["criteria"]
    assert criterion["target_count"] == 3

    assert [
             @old_grove_room_id,
             @wild_apple_room_id,
             @forgotten_corner_room_id
           ] == criterion["spawn_room_ids"]

    # No apples in any spawn room yet — they spawn on accept_quest.
    assert [] = objects_in_room(@old_grove_room_id)
    assert [] = objects_in_room(@wild_apple_room_id)
    assert [] = objects_in_room(@forgotten_corner_room_id)

    # ── US1 — Alice accepts the quest (mocking the LLM tool call by
    # invoking the wrapper directly; the path is the same as what the
    # Conversation module dispatches in production). ────────────────────
    assert {:ok, alice_qid} =
             WorldCommands.accept_quest(alice.id, @blueprint_id, @slug)

    # quest_instances row inserted (with state="active").
    assert %QuestInstance{state: "active", player_id: alice_pid_db, slug: @slug} =
             Quests.quest_instance(alice_qid)

    assert alice_pid_db == alice.id

    # Quest-item spawns are projected asynchronously (EntityProjector reacts to
    # the clone/move events the QuestAccepted handler dispatches); under
    # full-suite load that lags, so wait for all three before reading.
    wait_for_quest_items(@alice_spawn_rooms, alice_qid, 1)

    # Three apples spawned, one per spawn room, scoped to Alice.
    [alice_apple_old] = quest_objects_in_room(@old_grove_room_id, alice_qid)
    [alice_apple_wild] = quest_objects_in_room(@wild_apple_room_id, alice_qid)
    [alice_apple_corner] = quest_objects_in_room(@forgotten_corner_room_id, alice_qid)

    assert alice_apple_old.quest_player_id == alice.id
    assert alice_apple_wild.quest_player_id == alice.id
    assert alice_apple_corner.quest_player_id == alice.id

    # ── Multi-player isolation (SC-003) — Bob accepts the same quest.
    assert {:ok, bob_qid} =
             WorldCommands.accept_quest(bob.id, @blueprint_id, @slug)

    assert bob_qid != alice_qid

    wait_for_quest_items(@alice_spawn_rooms, bob_qid, 1)

    # Each spawn room now contains TWO apples (one per quest instance);
    # the per-viewer query filters them per player.
    assert 2 ==
             Repo.aggregate(
               from(o in Object,
                 where: o.container_type == "room" and o.container_id == ^@old_grove_room_id
               ),
               :count
             )

    # Per-viewer rendering filters correctly:
    alice_visible = Queries.list_objects_in_room_for_viewer(@old_grove_room_id, alice.id)
    bob_visible = Queries.list_objects_in_room_for_viewer(@old_grove_room_id, bob.id)

    assert length(alice_visible) == 1
    assert length(bob_visible) == 1
    assert hd(alice_visible).id != hd(bob_visible).id

    # ── FR-009 (a) — Alice cannot re-accept her active quest.
    assert {:error, :already_active, ^alice_qid} =
             WorldCommands.accept_quest(alice.id, @blueprint_id, @slug)

    # ── US2 — Alice picks up an apple and her progress updates.
    # Move Alice to the Old Apple Grove room first so `take` works.
    teleport_player(alice.id, @old_grove_room_id)

    # mount Alice's LiveView to drive PubSub assertions.
    {:ok, alice_view, _html} = live(alice_conn, ~p"/play")
    assert render(alice_view) =~ "0 / 3"

    {:ok, _} = WorldCommands.take(alice.id, "golden apple")

    # Progress is now 1/3 for Alice. Eventually-consistent broadcasts
    # are wired through UIEventBroadcaster.
    assert_eventually(alice_view, fn -> render(alice_view) =~ "1 / 3" end)

    # Bob's instance is unaffected.
    bob_progress = Quests.progress_for(Quests.quest_instance(bob_qid))
    assert [%{count: 0, target: 3}] = bob_progress

    # Alice's bookkeeping: the apple moved out of the room into her
    # inventory but stayed quest-scoped (still visible only to her).
    alice_inv = Queries.list_inventory(alice.id)
    assert Enum.any?(alice_inv, &(&1.name == "golden apple"))

    # Dropping a tagged item rolls progress back down.
    {:ok, _} = WorldCommands.drop(alice.id, "golden apple")
    assert_eventually(alice_view, fn -> render(alice_view) =~ "0 / 3" end)

    # Pick it back up and grab the other two.
    {:ok, _} = WorldCommands.take(alice.id, "golden apple")
    teleport_player(alice.id, @wild_apple_room_id)
    {:ok, _} = WorldCommands.take(alice.id, "golden apple")
    teleport_player(alice.id, @forgotten_corner_room_id)
    {:ok, _} = WorldCommands.take(alice.id, "golden apple")

    assert_eventually(alice_view, fn -> render(alice_view) =~ "3 / 3" end)

    # ── US3 — Finalize Alice's quest.
    teleport_player(alice.id, @cottage_room_id)
    assert {:ok, finalize_result} = WorldCommands.finalize_quest(alice.id, alice_qid)

    assert finalize_result.reward_name == "bigger golden apple"

    # quest_instances row flipped to "completed" (eventually — the
    # QuestProjector runs with :eventual consistency).
    assert_eventually(alice_view, fn ->
      case Quests.quest_instance(alice_qid) do
        %QuestInstance{state: "completed"} -> true
        _ -> false
      end
    end)

    # The three small apples are gone, the reward is in Alice's inventory.
    assert_eventually(alice_view, fn ->
      inv = Queries.list_inventory(alice.id)

      Enum.any?(inv, &(&1.name == "bigger golden apple")) and
        not Enum.any?(inv, &(&1.name == "golden apple"))
    end)

    # The inventory SIDE PANEL must reflect the finalize live, without a
    # manual `inv` re-query. QuestItemsConsumed / QuestRewardMinted now
    # surface PlayerInventoryChanged broadcasts that GameLive applies to the
    # :inventory assign in place. Scoped to the `.inv-list` panel so it can't
    # be satisfied by the quest-completion log line (which also names the
    # reward). The `<span>golden apple</span>` check is exact-tag so the
    # reward's "bigger golden apple" doesn't count as a leftover small apple.
    assert_eventually(alice_view, fn ->
      panel = render(element(alice_view, ".inv-list"))
      panel =~ "bigger golden apple" and not (panel =~ "<span>golden apple</span>")
    end)

    # ── FR-012 — sticky completion. Alice cannot re-accept.
    assert {:error, :already_completed} =
             WorldCommands.accept_quest(alice.id, @blueprint_id, @slug)

    # ── Bob's quest is still active and untouched.
    assert %QuestInstance{state: "active"} = Quests.quest_instance(bob_qid)

    bob_apples_count =
      Repo.aggregate(
        from(o in Object,
          where:
            o.quest_instance_id == ^bob_qid and o.container_type == "player" and
              o.container_id == ^Integer.to_string(bob.id)
        ),
        :count
      )

    assert bob_apples_count == 0,
           "Bob should not be carrying any apples — only Alice's quest was finalized"

    bob_room_apples =
      Repo.aggregate(
        from(o in Object,
          where: o.quest_instance_id == ^bob_qid and o.container_type == "room"
        ),
        :count
      )

    assert bob_room_apples == 3,
           "Bob's three quest apples should still be in their spawn rooms"
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp objects_in_room(room_id) do
    Repo.all(from(o in Object, where: o.container_type == "room" and o.container_id == ^room_id))
  end

  # Quest items spawn via async EntityProjector writes; poll until each room
  # holds the expected count so the reads below don't race the projection.
  defp wait_for_quest_items(room_ids, quest_id, per_room, timeout_ms \\ 3_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_quest_items(room_ids, quest_id, per_room, deadline)
  end

  defp do_wait_for_quest_items(room_ids, quest_id, per_room, deadline) do
    ready? =
      Enum.all?(room_ids, fn r -> length(quest_objects_in_room(r, quest_id)) >= per_room end)

    cond do
      ready? ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        :ok

      true ->
        Process.sleep(20)
        do_wait_for_quest_items(room_ids, quest_id, per_room, deadline)
    end
  end

  defp quest_objects_in_room(room_id, quest_id) do
    Repo.all(
      from(o in Object,
        where:
          o.container_type == "room" and o.container_id == ^room_id and
            o.quest_instance_id == ^quest_id
      )
    )
  end

  defp teleport_player(player_id, target_room_id) do
    # Bypass the move-with-exit-validation path for testing — directly
    # update player_state. This is acceptable because we're not testing
    # movement here; we're testing quest mechanics in isolation.
    from(ps in AgenticRealms.World.Schemas.PlayerState,
      where: ps.player_id == ^player_id
    )
    |> Repo.update_all(set: [current_room_id: target_room_id])

    :ok
  end
end
