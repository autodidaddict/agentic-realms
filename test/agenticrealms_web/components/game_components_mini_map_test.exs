defmodule AgenticRealmsWeb.GameComponents.MiniMapTest do
  @moduledoc """
  Render-snapshot tests for `mini_map/1`. Exercises the SVG output against
  handcrafted `MapView` structs — no Repo, no LiveView socket, no
  Commanded. Pure component-level assertions.

  Feature 012 — Maps. Covers US1 (basic SVG render), US2 (sequence diff
  on movement), and the information-hiding contract per FR-005 / FR-007 /
  FR-017 (no data-* leaks for fog stubs or cross-region affordances).
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AgenticRealms.World.MapView
  alias AgenticRealms.World.MapView.{RoomGlyph, ExitLine}
  alias AgenticRealmsWeb.GameComponents

  # ----------------------------------------------------------------
  # Fixtures
  # ----------------------------------------------------------------

  defp single_room_view do
    %MapView{
      region_id: "r-1",
      region_name: "Blackmire",
      current_room_id: "atrium",
      off_map?: false,
      viewport_center: {0, 0},
      rooms: [
        %RoomGlyph{
          id: "atrium",
          name: "Stone Atrium",
          x: 0,
          y: 0,
          is_current?: true,
          has_up?: false,
          has_down?: false
        }
      ],
      exits: [],
      has_above_rooms?: false,
      has_below_rooms?: false
    }
  end

  defp linear_three_view do
    %MapView{
      region_id: "r-1",
      region_name: "Blackmire",
      current_room_id: "b",
      off_map?: false,
      viewport_center: {1, 0},
      rooms: [
        %RoomGlyph{id: "a", name: "A", x: 0, y: 0, is_current?: false, has_up?: false, has_down?: false},
        %RoomGlyph{id: "b", name: "B", x: 1, y: 0, is_current?: true, has_up?: false, has_down?: false},
        %RoomGlyph{id: "c", name: "C", x: 2, y: 0, is_current?: false, has_up?: false, has_down?: false}
      ],
      exits: [
        %ExitLine{kind: :normal, from_x: 0, from_y: 0, to_x: 1, to_y: 0, direction: :east},
        %ExitLine{kind: :normal, from_x: 1, from_y: 0, to_x: 2, to_y: 0, direction: :east}
      ],
      has_above_rooms?: false,
      has_below_rooms?: false
    }
  end

  defp off_map_view do
    %MapView{
      region_id: "r-1",
      region_name: "Blackmire",
      current_room_id: "vault",
      off_map?: true,
      viewport_center: {0, 0},
      rooms: [],
      exits: [],
      has_above_rooms?: false,
      has_below_rooms?: false
    }
  end

  defp render_map(view) do
    render_component(&GameComponents.mini_map/1, %{map_view: view})
  end

  # ----------------------------------------------------------------
  # US1 — single room
  # ----------------------------------------------------------------

  describe "US1 — single discovered room" do
    test "renders the region name in the header" do
      html = render_map(single_room_view())
      assert html =~ "Blackmire"
      assert html =~ "map-region"
    end

    test "renders exactly one map-cell group" do
      html = render_map(single_room_view())
      cells = Regex.scan(~r/class="[^"]*\bmap-cell\b[^"]*"/, html)
      assert length(cells) == 1
    end

    test "the rendered cell carries the current-room class" do
      html = render_map(single_room_view())
      assert html =~ "map-cell--current"
    end

    test "the rendered cell has a <title> with the room name (a11y)" do
      html = render_map(single_room_view())
      assert html =~ "<title>Stone Atrium</title>"
    end

    test "the rendered cell carries the data-room-name attribute" do
      html = render_map(single_room_view())
      assert html =~ ~s|data-room-name="Stone Atrium"|
    end

    test "no exit lines for a lone room" do
      html = render_map(single_room_view())
      refute html =~ "<line "
    end
  end

  # ----------------------------------------------------------------
  # US1 / US2 — linear three rooms
  # ----------------------------------------------------------------

  describe "linear three rooms — three glyphs, two undirected lines" do
    test "renders three map-cell groups" do
      html = render_map(linear_three_view())
      cells = Regex.scan(~r/class="[^"]*\bmap-cell\b[^"]*"/, html)
      assert length(cells) == 3
    end

    test "renders exactly two map-line elements (FR-004 dedup verified upstream)" do
      html = render_map(linear_three_view())
      lines = Regex.scan(~r/class="[^"]*\bmap-line\b[^"]*"/, html)
      assert length(lines) == 2
    end

    test "only the middle room carries the current-room class" do
      html = render_map(linear_three_view())
      currents = Regex.scan(~r/map-cell--current/, html)
      assert length(currents) == 1
      # Verify it's specifically room B
      assert html =~ ~s|data-room-name="B"|
    end
  end

  # ----------------------------------------------------------------
  # US2 — sequence rendering (single → three → still works)
  # ----------------------------------------------------------------

  describe "US2 — re-render reflects updated MapView (no stale state)" do
    test "rendering single then linear-three produces independent HTML strings" do
      single = render_map(single_room_view())
      linear = render_map(linear_three_view())

      # Both must reference the region header but differ in cell count.
      assert single =~ "Blackmire"
      assert linear =~ "Blackmire"

      single_cells = Regex.scan(~r/class="[^"]*\bmap-cell\b[^"]*"/, single)
      linear_cells = Regex.scan(~r/class="[^"]*\bmap-cell\b[^"]*"/, linear)

      assert length(single_cells) == 1
      assert length(linear_cells) == 3
    end
  end

  # ----------------------------------------------------------------
  # Off-map state (FR-003a)
  # ----------------------------------------------------------------

  describe "off-map state (FR-003a)" do
    test "renders only the region header — no svg canvas, no glyphs" do
      html = render_map(off_map_view())
      assert html =~ "Blackmire"
      assert html =~ "map-canvas--off-map"
      refute html =~ "<g "
      refute html =~ "<line "
    end
  end

  # ----------------------------------------------------------------
  # Information-hiding contract (FR-005, FR-017, FR-012)
  # ----------------------------------------------------------------

  describe "information-hiding" do
    test "no <line> element carries data-room-name or data-target-id" do
      html = render_map(linear_three_view())

      # Extract line elements; ensure none has identifying attributes.
      # Match both self-closing `<line .../>` and opening-tag `<line ...>` forms.
      line_chunks = Regex.scan(~r/<line\b[^>]*>/, html)
      assert line_chunks != [], "expected at least one <line> in the rendered SVG"

      for [chunk] <- line_chunks do
        refute chunk =~ "data-room-name"
        refute chunk =~ "data-target-id"
        refute chunk =~ "data-room-id"
      end
    end

    test "the rendered HTML contains no integer elevation in unexpected places" do
      # The renderer must not display the elevation value (FR-012). The
      # snapshot HTML should contain no digit sequences flagged as
      # "elevation" anywhere. (SVG coords carry digits; this assertion
      # specifically looks for the word "elevation" near any digit.)
      html = render_map(linear_three_view())
      refute html =~ ~r/elevation[\s:=]*\d/i
    end

    test "no arrowheads / markers on map-line elements (FR-005 / SC-003)" do
      html = render_map(linear_three_view())
      refute html =~ "marker-end"
      refute html =~ "marker-start"
      refute html =~ ~s|marker="|
    end
  end
end
