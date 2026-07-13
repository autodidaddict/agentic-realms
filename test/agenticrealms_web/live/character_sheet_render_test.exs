defmodule AgenticRealmsWeb.CharacterSheetRenderTest do
  @moduledoc """
  Feature 019 US1 — the character sheet renders the player's real, persisted
  stats and contains no mock values. Tagged `:integration` (mounts the full
  GameLive); run with:

      mix test --include integration \\
        test/agenticrealms_web/live/character_sheet_render_test.exs
  """
  use AgenticRealmsWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag :commanded

  import Phoenix.LiveViewTest

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.{Commands, Seed}

  setup %{conn: conn} do
    try do
      Seed.run()
    rescue
      MatchError -> :already_seeded
    end

    Req.Test.set_req_test_to_shared(%{})
    suffix = System.unique_integer([:positive])

    {:ok, alice} =
      Accounts.register_player(%{username: "sheet_#{suffix}", password: "pw12345678"})

    {:ok, _} = Commands.spawn(alice.id, Seed.starting_room_id())

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, alice.id)

    %{conn: conn, alice: alice}
  end

  test "sidebar + modal show real defaults and no mock stats", %{conn: conn, alice: alice} do
    {:ok, view, html} = live(conn, ~p"/play")

    # Sidebar Character card: real name, level, and real vitals.
    assert html =~ alice.username
    assert html =~ "Lvl 1"
    assert html =~ "Level 1"
    # HP 10/10 and Mana 10/10 both render as "10 / 10".
    assert html =~ "10 / 10"

    # No mock values anywhere.
    refute html =~ "Veyr of Ashfall"
    refute html =~ "Cleric"

    # Open the Character Sheet modal and check the ability grid + no mock flavor.
    modal_html = render_click(view, "open_modal", %{"modal" => "stats"})

    assert modal_html =~ "Strength"
    assert modal_html =~ "Charisma"
    assert modal_html =~ "xp to level 2"
    refute modal_html =~ "Devoted to the Dawnbringer"
    refute modal_html =~ "Channel Dawnlight"
    refute modal_html =~ "Regenerates slowly"
  end
end
