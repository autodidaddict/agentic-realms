defmodule AgenticRealmsWeb.CharacterSheetRenderTest do
  @moduledoc """
  Feature 020 US1 — the character sheet renders the viewing player's real SRD
  character across three tabs, with no mana and no mock values. Tagged
  `:integration` (mounts the full GameLive); run with:

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

    # Feature 021 — a character before a world. Without one, mounting lands in
    # the creation dialog rather than the game.
    AgenticRealms.DataCase.create_character!(alice.id, name: "Sheet#{suffix}")

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:player_id, alice.id)

    %{conn: conn, alice: alice}
  end

  defp open_sheet(conn) do
    {:ok, view, html} = live(conn, ~p"/play")
    {view, html, render_click(view, "open_modal", %{"modal" => "stats"})}
  end

  describe "the sidebar" do
    test "shows the character, not a placeholder", %{conn: conn, alice: alice} do
      {_view, html, _sheet} = open_sheet(conn)

      assert html =~ alice.username
      assert html =~ "Lvl 1"
      assert html =~ "Level 1 Human Fighter"
      # A level 1 Fighter with Constitution +2 has 12 hitpoints.
      assert html =~ "12 / 12"

      refute html =~ "Veyr of Ashfall"
      refute html =~ "Cleric"
    end

    test "has no mana bar (FR-033)", %{conn: conn} do
      {_view, html, _sheet} = open_sheet(conn)

      refute html =~ ~r/mana/i
    end
  end

  describe "the tab strip" do
    test "renders all three tabs", %{conn: conn} do
      {_view, _html, sheet} = open_sheet(conn)

      assert sheet =~ "Main Stats"
      assert sheet =~ "Abilities"
      assert sheet =~ "Spells"
      assert sheet =~ ~s(role="tablist")
    end

    test "opens on the main tab with the others hidden (FR-020)", %{conn: conn} do
      {_view, _html, sheet} = open_sheet(conn)

      assert sheet =~ ~s(id="sheet-tab-main" class="sheet-tab active")
      assert sheet =~ ~r/id="sheet-panel-abilities".*?display: none/s
      assert sheet =~ ~r/id="sheet-panel-spells".*?display: none/s
    end

    test "switching tabs never reaches the server (FR-019)", %{conn: conn} do
      {_view, _html, sheet} = open_sheet(conn)

      # Every tab button carries a client-side JS command, not a server event
      # name. A bare phx-click="select_tab" would be a round trip.
      refute sheet =~ ~s(phx-click="select_tab")
      assert sheet =~ ~s([&quot;show&quot;)
    end

    test "all three panels are in the DOM at once", %{conn: conn} do
      {_view, _html, sheet} = open_sheet(conn)

      for tab <- ~w(main abilities spells) do
        assert sheet =~ ~s(id="sheet-panel-#{tab}")
        assert sheet =~ ~s(role="tabpanel")
      end
    end
  end

  describe "the main tab" do
    test "shows identity, vitals and the derived combat values (FR-016)", %{conn: conn} do
      {_view, _html, sheet} = open_sheet(conn)

      assert sheet =~ "Human Fighter"
      assert sheet =~ "Background"
      assert sheet =~ "Soldier"

      assert sheet =~ "Armor Class"
      assert sheet =~ "Initiative"
      assert sheet =~ "Proficiency"
      assert sheet =~ "Passive Perception"
      assert sheet =~ "Movement"
      assert sheet =~ "30 ft."
      assert sheet =~ "Size"
      assert sheet =~ "Medium"
      assert sheet =~ "Hit Dice"
      assert sheet =~ "1d10"
    end

    test "experience counts toward the SRD level 2 threshold", %{conn: conn} do
      {_view, _html, sheet} = open_sheet(conn)

      assert sheet =~ "300 xp to level 2"
    end
  end

  describe "the abilities tab" do
    test "lists all six scores with signed modifiers (FR-007, FR-017)", %{conn: conn} do
      {_view, _html, sheet} = open_sheet(conn)

      for name <- ~w(Strength Dexterity Constitution Intelligence Wisdom Charisma) do
        assert sheet =~ name
      end

      assert sheet =~ "Ability Scores"
      # Strength 17 is +3; Charisma 8 is -1.
      assert sheet =~ "+3"
      assert sheet =~ "-1"
    end

    test "lists saving throws and all eighteen skills", %{conn: conn} do
      {_view, _html, sheet} = open_sheet(conn)

      assert sheet =~ "Saving Throws"
      assert sheet =~ "Skills"

      for skill <- ["Acrobatics", "Animal Handling", "Sleight of Hand", "Survival"] do
        assert sheet =~ skill
      end
    end

    test "marks proficiency without relying on colour", %{conn: conn} do
      {_view, _html, sheet} = open_sheet(conn)

      assert sheet =~ "Athletics: proficient"
      assert sheet =~ "Stealth: not proficient"
      assert sheet =~ "Strength saving throw: proficient"
    end
  end

  describe "the spells tab" do
    test "is an explicit placeholder with no spell data (FR-018)", %{conn: conn} do
      {_view, _html, sheet} = open_sheet(conn)

      assert sheet =~ "Spellcasting is not yet available."
      refute sheet =~ "Spell Slots"
      refute sheet =~ "Cantrips"
    end
  end

  describe "closing" do
    test "escape closes the whole sheet from any tab (FR-021)", %{conn: conn} do
      {view, _html, sheet} = open_sheet(conn)

      assert sheet =~ "Character Sheet"
      after_close = render_click(view, "close_modal", %{})
      refute after_close =~ "Character Sheet"
    end
  end
end
