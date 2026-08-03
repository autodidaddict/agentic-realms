defmodule AgenticRealmsWeb.GameLiveIntentParserTest do
  @moduledoc """
  End-to-end LiveView test for feature 005 (natural-language intent parser).

  Structured as a single comprehensive test exercising US1 (success path),
  US2 (refusal), and US3 (resilience) in sequence — one `Seed.run` setup,
  one mounted LiveView. Multiple per-test setups conflict with the in-memory
  event store accumulating state across the suite (same constraint that
  shaped the 004 LiveView tests).

  Tagged `:integration` and excluded from the default `mix test` run. Run with
  `mix test --include integration test/agenticrealms_web/live/game_live_intent_parser_test.exs`.

  The intent resolver runs in a Task spawned off the LiveView, so the test
  puts `Req.Test` in shared mode — the Task process can then reach the stub
  registered here.
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
    {:ok, player} = Accounts.register_player(%{username: "ip_#{suffix}", password: "pw12345678"})
    AgenticRealms.DataCase.create_character!(player.id, name: player.username)
    {:ok, _} = Commands.spawn(player.id, Seed.starting_room_id())

    player_conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, player.id)

    %{player: player, player_conn: player_conn}
  end

  test "natural-language input resolves, refuses, and survives API failure",
       %{player_conn: conn, player: player} do
    {:ok, view, _html} = live(conn, ~p"/play")
    flush(view)

    lantern_name = first_object_name(player.id)

    stub_tool_use("take", %{"object" => lantern_name})

    submit(view, "grab the #{lantern_name} off the floor")
    await_unlock(view)

    html = render(view)

    assert html =~ "grab the #{lantern_name} off the floor",
           "the player's literal input should be echoed as a :cmd entry"

    assert html =~ "You take the #{lantern_name}",
           "the resolved take action should produce the standard confirmation"

    assert lantern_name in Enum.map(Queries.list_inventory(player.id), & &1.name),
           "the lantern should now be in the player's inventory"

    stub_tool_use("refuse", %{"message" => "Combat is not supported yet."})

    inventory_before = Queries.list_inventory(player.id)
    submit(view, "attack the orc with my bare hands")
    await_unlock(view)

    html = render(view)
    assert html =~ "Combat is not supported yet."

    assert Queries.list_inventory(player.id) == inventory_before,
           "a refusal must not change game state"

    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      Plug.Conn.send_resp(conn, 500, ~s({"error": "overloaded"}))
    end)

    submit(view, "do something the parser cannot handle either")
    await_unlock(view)

    html = render(view)

    assert html =~ "not sure what you meant just now",
           "an API failure should produce the graceful refusal"

    submit(view, "look")
    flush(view)
    assert render(view) =~ "Stone Atrium"

    assert lantern_name in Enum.map(Queries.list_inventory(player.id), & &1.name),
           "precondition: the lantern is still carried"

    stub_tool_use("drop", %{"object" => lantern_name})

    submit(view, "drop the lantern")
    await_unlock(view)

    html = render(view)

    assert html =~ "You drop the #{lantern_name}",
           "a fast-path drop that fails name resolution should fall back to the LLM and succeed"

    refute lantern_name in Enum.map(Queries.list_inventory(player.id), & &1.name),
           "the lantern should no longer be carried after the resolved drop"

    assert cmd_echo_count(html, "drop the lantern") == 1,
           "the literal input must be echoed exactly once, not doubled by the fallback"

    stub_tool_use("take", %{"object" => lantern_name})
    submit(view, "grab the lantern again")
    await_unlock(view)

    stub_tool_use("look", %{"target" => lantern_name})
    submit(view, "examine my lantern up close")
    await_unlock(view)

    html = render(view)

    assert html =~ ~s(class="log-entry detail detail-object"),
           "a look-target tool call should render a :detail entry via the fallback path"

    assert html =~ ~s(class="log-entry cmd">examine my lantern up close</div>),
           "the literal natural-language input should be echoed once"

    stub_tool_use("look", %{"target" => "me"})
    submit(view, "look at myself")
    await_unlock(view)

    html = render(view)

    assert html =~ ~s(class="log-entry detail detail-player"),
           "a self-look tool call should render a :detail player entry"

    assert html =~ "#{player.username}</span> is a player.",
           "self-examine should render the acting player's name"
  end

  defp stub_tool_use(tool_name, input) do
    Req.Test.stub(AgenticRealms.Anthropic, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{"type" => "tool_use", "id" => "toolu_test", "name" => tool_name, "input" => input}
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

  defp cmd_echo_count(html, text) do
    html
    |> String.split(~s(class="log-entry cmd">#{text}</div>))
    |> length()
    |> Kernel.-(1)
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

  defp first_object_name(player_id) do
    {:ok, room} = Queries.look_room(player_id)

    case room.objects do
      [obj | _] -> obj.name
      [] -> flunk("expected the starting room to contain a takeable object")
    end
  end
end
