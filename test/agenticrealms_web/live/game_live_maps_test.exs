defmodule AgenticRealmsWeb.GameLiveMapsTest do
  @moduledoc """
  End-to-end LiveView test exercising US1 through US7 against the seeded
  Blackmire + Hollowvale world.

  Feature 012 — Maps. Tagged `:integration` so it runs alongside the
  other integration suites (e.g., game_live_behaviors_test.exs). The
  whole story is a single sequential test so the seed runs exactly once
  per module — see the moduledoc comment in `World.Seed` for why the
  Commanded aggregate state persists across sandbox-isolated tests.
  """

  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.Commands
  alias AgenticRealms.World.Seed

  setup %{conn: conn} do
    Seed.run()

    {:ok, player} =
      Accounts.register_player(%{
        username: "maps_test_#{System.unique_integer([:positive])}",
        password: "pw12345678"
      })

    {:ok, _} = Commands.spawn(player.id, Seed.starting_room_id())

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, player.id)

    %{conn: conn, player: player}
  end

  test "US1-US7 sequence against the seeded Blackmire + Hollowvale world", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")

    # ----- US1 — region header + current-room highlight -----------------
    html_us1 = render_click(view, "toggle_map", %{})

    assert html_us1 =~ "Blackmire", "US1: region header reads Blackmire"
    assert html_us1 =~ "map-cell--current", "US1: current-room highlight present"
    assert html_us1 =~ ~s|data-room-name="Stone Atrium"|, "US1: Atrium glyph rendered"

    # ----- US3 — fog stubs for undiscovered visible neighbors -----------
    # At spawn time the Atrium's exits to Corridor, Library, Border-via-
    # Library, etc. lead to undiscovered visible rooms. They render as
    # fog stubs with NO data-room-name.
    assert html_us1 =~ "map-fog-stub", "US3: at least one fog stub renders"
    assert html_us1 =~ "map-fog-cloud", "US3: hatched cloud at fog endpoint"

    for [chunk] <- Regex.scan(~r/<line[^>]*map-fog-stub[^>]*>/, html_us1) do
      refute chunk =~ "data-room-name", "US3: fog stub line carries no data-room-name"
    end

    # ----- US4 — Up icon on Atrium; switch elevation -------------------
    assert html_us1 =~ "map-icon-up", "US4: Atrium has Up icon"

    html_in_loft = render_submit(view, "submit_command", %{"text" => "up"})

    assert html_in_loft =~ ~s|data-room-name="Atrium Loft"|, "US4: Loft is current"
    assert html_in_loft =~ "map-icon-down", "US4: Loft has Down icon"
    assert html_in_loft =~ "map-affordance--below", "US4: below-rooms pip"

    refute html_in_loft =~ ~r/elevation[\s:="]*\d/i,
           "FR-012 / SC-008: no integer elevation in markup"

    # Back to ground.
    _ = render_submit(view, "submit_command", %{"text" => "down"})

    # ----- US2 — moving updates the map --------------------------------
    html_after_n = render_submit(view, "submit_command", %{"text" => "north"})

    assert html_after_n =~ ~s|data-room-name="North Corridor"|, "US2: Corridor newly rendered"
    assert html_after_n =~ ~s|data-room-name="Stone Atrium"|, "US2: Atrium remains discovered"

    currents = Regex.scan(~r/map-cell--current/, html_after_n)
    assert length(currents) == 1, "US2: exactly one current-room highlight"

    # Walk back south.
    _ = render_submit(view, "submit_command", %{"text" => "south"})

    # ----- US5 — hidden Vault blanks the map --------------------------
    _ = render_submit(view, "submit_command", %{"text" => "east"})
    html_in_vault = render_submit(view, "submit_command", %{"text" => "east"})

    assert html_in_vault =~ "Blackmire", "US5: region header preserved while off-map"
    assert html_in_vault =~ "map-canvas--off-map", "US5: blank canvas in Vault"

    refute html_in_vault =~ ~s|data-room-name="Hidden Vault"|,
           "US5: Vault never appears as a glyph"

    # Walk back west to the Library, then south to the Border.
    _ = render_submit(view, "submit_command", %{"text" => "west"})
    html_at_border = render_submit(view, "submit_command", %{"text" => "south"})

    # ----- US6 — cross-region affordance and region swap --------------
    assert html_at_border =~ "Blackmire"

    assert html_at_border =~ "map-line--cross-region",
           "US6: Border's east exit renders as cross-region affordance"

    for [chunk] <- Regex.scan(~r/<line[^>]*map-line--cross-region[^>]*>/, html_at_border) do
      refute chunk =~ "data-room-name", "US6: cross-region line carries no data-room-name"
    end

    html_in_hollowvale = render_submit(view, "submit_command", %{"text" => "east"})

    assert html_in_hollowvale =~ "Hollowvale", "US6: header swaps to Hollowvale"
    assert html_in_hollowvale =~ ~s|data-room-name="Hollowvale Outskirts"|

    # ----- US7 — hover tooltip plumbing (client-side) ------------------
    # The tooltip is rendered entirely by the .MapTooltip ColocatedHook
    # in the browser; the LiveView is not involved per-hover. Verify the
    # data-room-name + aria-label primitives that the hook reads are
    # present on the rendered cells.
    assert html_in_hollowvale =~ ~s|data-room-name="Hollowvale Outskirts"|
    assert html_in_hollowvale =~ ~s|aria-label="Hollowvale Outskirts"|

    # ----- Cross-cutting audits ---------------------------------------
    refute html_in_hollowvale =~ "marker-end", "SC-003: no arrowheads"
    refute html_in_hollowvale =~ "marker-start", "SC-003: no arrowheads"
  end
end
