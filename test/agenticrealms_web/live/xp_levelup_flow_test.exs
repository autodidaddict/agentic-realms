defmodule AgenticRealmsWeb.XpLevelupFlowTest do
  @moduledoc """
  Feature 019 US2 — completing a quest awards its xp to the Player aggregate,
  which levels up and notifies the player; the character sheet updates live.

  Tagged `:integration`; run with:

      mix test --include integration \\
        test/agenticrealms_web/live/xp_levelup_flow_test.exs
  """
  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Commands, as: WorldCommands
  alias AgenticRealms.World.Seed
  alias AgenticRealms.World.Schemas.{Object, PlayerState}

  @blueprint_id "amaranth_the_orchard_keeper"
  @slug "golden_apples"
  @cottage_room_id "00000000-0000-4000-8000-000000000008"
  @old_grove_room_id "00000000-0000-4000-8000-000000000009"
  @wild_apple_room_id "00000000-0000-4000-8000-00000000000a"
  @forgotten_corner_room_id "00000000-0000-4000-8000-00000000000b"
  @spawn_rooms [@old_grove_room_id, @wild_apple_room_id, @forgotten_corner_room_id]

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    Req.Test.set_req_test_to_shared(%{})
    suffix = System.unique_integer([:positive])

    {:ok, alice} = Accounts.register_player(%{username: "xp_#{suffix}", password: "pw12345678"})
    # Feature 020 — mount creates the character before spawning; this setup
    # bypasses mount, so it does the same two dispatches in the same order.
    AgenticRealms.DataCase.create_character!(alice.id, name: alice.username)
    AgenticRealms.DataCase.create_character!(alice.id, name: alice.username)
    {:ok, _} = WorldCommands.spawn(alice.id, Seed.starting_room_id())

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, alice.id)

    %{conn: conn, alice: alice}
  end

  test "orchard quest grants 300 xp → Level 2 + chat notices + live sheet",
       %{conn: conn, alice: alice} do
    # Fresh player: default stats.
    assert %PlayerState{level: 1, xp: 0} = Repo.get(PlayerState, alice.id)

    {:ok, qid} = WorldCommands.accept_quest(alice.id, @blueprint_id, @slug)
    wait_for_quest_items(@spawn_rooms, qid, 1)

    # Collect all three apples.
    for room <- @spawn_rooms do
      teleport(alice.id, room)
      {:ok, _} = WorldCommands.take(alice.id, "golden apple")
    end

    # Mount BEFORE finalize so the LiveView catches the progression broadcasts.
    {:ok, view, _html} = live(conn, ~p"/play")

    teleport(alice.id, @cottage_room_id)
    assert {:ok, _} = WorldCommands.finalize_quest(alice.id, qid)

    # Projector lands the new xp/level (XpAwarder is :eventual → poll).
    assert_eventually(view, fn ->
      match?(%PlayerState{level: 2, xp: 300}, Repo.get(PlayerState, alice.id))
    end)

    # Chat-window notices (FR-022, FR-023).
    assert_eventually(view, fn -> render(view) =~ "You gain 300 experience." end)
    assert_eventually(view, fn -> render(view) =~ "You are now level 2!" end)

    # The character sheet assign reflects Level 2 live.
    assert_eventually(view, fn -> :sys.get_state(view.pid).socket.assigns.stats.level == 2 end)
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp wait_for_quest_items(room_ids, quest_id, per_room, timeout_ms \\ 3_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait(room_ids, quest_id, per_room, deadline)
  end

  defp do_wait(room_ids, quest_id, per_room, deadline) do
    ready? =
      Enum.all?(room_ids, fn r ->
        Repo.aggregate(
          from(o in Object,
            where:
              o.container_type == "room" and o.container_id == ^r and
                o.quest_instance_id == ^quest_id
          ),
          :count
        ) >= per_room
      end)

    cond do
      ready? -> :ok
      System.monotonic_time(:millisecond) > deadline -> :ok
      true -> Process.sleep(20) && do_wait(room_ids, quest_id, per_room, deadline)
    end
  end

  defp teleport(player_id, room_id) do
    from(ps in PlayerState, where: ps.player_id == ^player_id)
    |> Repo.update_all(set: [current_room_id: room_id])

    :ok
  end
end
