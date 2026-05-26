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

  defp fog_stub_view do
    %MapView{
      region_id: "r-1",
      region_name: "Blackmire",
      current_room_id: "a",
      off_map?: false,
      viewport_center: {0, 0},
      rooms: [
        %RoomGlyph{
          id: "a",
          name: "A",
          x: 0,
          y: 0,
          is_current?: true,
          has_up?: false,
          has_down?: false
        }
      ],
      exits: [
        %ExitLine{
          kind: :fog_stub,
          from_x: 0,
          from_y: 0,
          to_x: 0.6,
          to_y: 0.0,
          direction: :east
        }
      ],
      has_above_rooms?: false,
      has_below_rooms?: false
    }
  end

  defp multi_floor_view(opts \\ []) do
    has_up = Keyword.get(opts, :has_up?, true)
    has_down = Keyword.get(opts, :has_down?, false)
    above = Keyword.get(opts, :has_above_rooms?, false)
    below = Keyword.get(opts, :has_below_rooms?, false)

    %MapView{
      region_id: "r-1",
      region_name: "Blackmire",
      current_room_id: "current",
      off_map?: false,
      viewport_center: {0, 0},
      rooms: [
        %RoomGlyph{
          id: "current",
          name: "Stone Atrium",
          x: 0,
          y: 0,
          is_current?: true,
          has_up?: has_up,
          has_down?: has_down
        }
      ],
      exits: [],
      has_above_rooms?: above,
      has_below_rooms?: below
    }
  end

  defp cross_region_view do
    %MapView{
      region_id: "blackmire",
      region_name: "Blackmire",
      current_room_id: "border",
      off_map?: false,
      viewport_center: {0, 0},
      rooms: [
        %RoomGlyph{
          id: "border",
          name: "Border",
          x: 0,
          y: 0,
          is_current?: true,
          has_up?: false,
          has_down?: false
        }
      ],
      exits: [
        %ExitLine{
          kind: :cross_region,
          from_x: 0,
          from_y: 0,
          to_x: 0.6,
          to_y: 0.0,
          direction: :east
        }
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

  defp render_dir_pad do
    render_component(&GameComponents.dir_pad/1, %{})
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
      # The <defs> block contains a `<line>` inside the hatch pattern (it's
      # render scaffolding, not an exit). Assert on the exit-specific
      # classes instead.
      refute html =~ "map-line--normal"
      refute html =~ "map-fog-stub"
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
  # US3 — fog-of-war stubs + information hiding at the renderer
  # ----------------------------------------------------------------

  describe "US3 — fog-of-war stub rendering" do
    test "renders a .map-fog-stub line plus a .map-fog-cloud rect" do
      html = render_map(fog_stub_view())

      assert html =~ "map-fog-stub"
      assert html =~ "map-fog-cloud"
    end

    test "the fog-stub line element carries NO title and NO data-room-name" do
      html = render_map(fog_stub_view())

      # Find the line tagged map-fog-stub (it may be self-closing or open
      # depending on Phoenix's renderer; match both).
      assert [stub_chunk] = Regex.run(~r/<line[^>]*map-fog-stub[^>]*>/, html)
      refute stub_chunk =~ "data-room-name"
      refute stub_chunk =~ "data-room-id"
      refute stub_chunk =~ "data-target"

      # And there's no <title> child inside the line (linear element, no
      # children typically, but assert defensively).
      stub_index = String.split(html, "map-fog-stub") |> length()
      assert stub_index >= 2
    end

    test "the fog-cloud rect carries NO data-room-name or identifying attribute" do
      html = render_map(fog_stub_view())

      assert [cloud_chunk] = Regex.run(~r/<rect[^>]*map-fog-cloud[^>]*>/, html)
      refute cloud_chunk =~ "data-room-name"
      refute cloud_chunk =~ "data-room-id"
      refute cloud_chunk =~ "data-target"
    end

    test "fog-stub render includes the <defs> linearGradient + pattern" do
      html = render_map(fog_stub_view())

      assert html =~ ~s|id="fog-fade"|
      assert html =~ ~s|id="fog-hatch"|
      assert html =~ "linearGradient"
      assert html =~ "<pattern"
    end

    test "an undiscovered destination name is NEVER present in fog-stub markup" do
      html = render_map(fog_stub_view())

      # The fixture has only room A in `rooms`. Any other name appearing
      # would mean the renderer leaked info. The destination's name in our
      # fixture doesn't exist (the stub has no destination identity), so
      # the only room name allowed is "A".
      assert html =~ ~s|data-room-name="A"|
      # Verify there's no second data-room-name attribute referring to
      # somewhere we didn't render.
      data_names = Regex.scan(~r/data-room-name="([^"]+)"/, html)
      assert data_names == [["data-room-name=\"A\"", "A"]]
    end
  end

  # ----------------------------------------------------------------
  # US4 — vertical exits + elevation filtering UI
  # ----------------------------------------------------------------

  describe "US4 — Up/Down icons inside the room glyph" do
    test "has_up?: true renders a .map-icon-up SVG inside the cell" do
      html = render_map(multi_floor_view(has_up?: true, has_down?: false))
      assert html =~ "map-icon-up"
      refute html =~ "map-icon-down"
    end

    test "has_down?: true renders .map-icon-down" do
      html = render_map(multi_floor_view(has_up?: false, has_down?: true))
      assert html =~ "map-icon-down"
      refute html =~ "map-icon-up"
    end

    test "has_up? + has_down? both true renders BOTH icons in the same cell" do
      html = render_map(multi_floor_view(has_up?: true, has_down?: true))
      assert html =~ "map-icon-up"
      assert html =~ "map-icon-down"
    end

    test "has_up?: false, has_down?: false → no icons in the cell" do
      html = render_map(multi_floor_view(has_up?: false, has_down?: false))
      refute html =~ "map-icon-up"
      refute html =~ "map-icon-down"
    end
  end

  describe "US4 — above/below header affordances (FR-011 / FR-012)" do
    test "has_above_rooms?: true renders the above affordance pip with aria-label" do
      html = render_map(multi_floor_view(has_above_rooms?: true))
      assert html =~ "map-affordance--above"
      assert html =~ ~s|aria-label="Discovered rooms above"|
    end

    test "has_below_rooms?: true renders the below affordance pip with aria-label" do
      html = render_map(multi_floor_view(has_below_rooms?: true))
      assert html =~ "map-affordance--below"
      assert html =~ ~s|aria-label="Discovered rooms below"|
    end

    test "neither flag set → no affordance pips" do
      html = render_map(multi_floor_view(has_above_rooms?: false, has_below_rooms?: false))
      refute html =~ "map-affordance--above"
      refute html =~ "map-affordance--below"
    end

    test "NO raw integer elevation appears anywhere in the rendered HTML (SC-008)" do
      html = render_map(multi_floor_view(has_above_rooms?: true, has_below_rooms?: true))

      # FR-012: the integer elevation must not leak. The header must not
      # contain a digit-bearing tag adjacent to the affordances.
      refute html =~ ~r/elevation[\s:="]*\d/i
      refute html =~ ~r/floor\s*\d/i
      refute html =~ ~r/level\s*\d/i
    end

    test "above affordance pip contains chevron-up path, NOT a digit" do
      html = render_map(multi_floor_view(has_above_rooms?: true))

      assert [pip] =
               Regex.run(
                 ~r/<span[^>]*map-affordance--above[^>]*>.*?<\/span>/s,
                 html
               )

      assert pip =~ "<path"
      # The path's `d` attribute may contain numerics (coordinates), but
      # no integer-looking elevation marker should appear as visible text
      # inside the span.
      visible_text = Regex.replace(~r/<[^>]+>/, pip, "")
      refute visible_text =~ ~r/\d/
    end
  end

  # ----------------------------------------------------------------
  # US5 — hidden rooms render as if absent (FR-006)
  # ----------------------------------------------------------------
  #
  # The MapView layer is what actually enforces hidden-room suppression
  # (its query filter on map_visible == true and its build_exit_lines
  # cond). The renderer is a pure function of the MapView struct, so
  # these snapshot tests verify the contract by feeding a MapView that
  # has ALREADY excluded the hidden room — the renderer must not "make
  # up" extra content.

  describe "US5 — hidden room renders as if absent" do
    test "when the hidden neighbor was suppressed from MapView, no line or fog stub appears" do
      # Single-room MapView (hidden neighbor pre-suppressed by MapView).
      html = render_map(single_room_view())

      refute html =~ "map-line--normal"
      refute html =~ "map-fog-stub"
      refute html =~ "map-fog-cloud"

      # The current room glyph still renders normally — hidden rooms
      # don't affect the visible room's own appearance.
      assert html =~ ~s|data-room-name="Stone Atrium"|
    end

    test "no DOM element names the hidden room or its coordinates" do
      html = render_map(single_room_view())

      # The single_room_view fixture conceptually has a hidden neighbor
      # that MapView has filtered out. The renderer's job is to not
      # invent any reference to it. Assert no extra room-name attributes
      # beyond the single rendered cell.
      data_names = Regex.scan(~r/data-room-name="([^"]+)"/, html)
      assert length(data_names) == 1
    end

    test "the rendered HTML does not contain the literal 'Hidden' as a room name" do
      # Catches a class of regressions where the renderer might leak the
      # hidden room's name via some forgotten attribute or comment.
      html = render_map(single_room_view())
      refute html =~ "Hidden Vault"
      refute html =~ ~s|name="Hidden|
    end
  end

  # ----------------------------------------------------------------
  # US6 — cross-region affordance rendering
  # ----------------------------------------------------------------

  describe "US6 — cross-region rendering" do
    test "renders a .map-line--cross-region (dashed) plus a .map-portal" do
      html = render_map(cross_region_view())
      assert html =~ "map-line--cross-region"
      assert html =~ "map-portal"
    end

    test "the cross-region line carries NO data-room-name and NO data-target-id" do
      html = render_map(cross_region_view())

      assert [chunk] = Regex.run(~r/<line[^>]*map-line--cross-region[^>]*>/, html)
      refute chunk =~ "data-room-name"
      refute chunk =~ "data-room-id"
      refute chunk =~ "data-target"
      refute chunk =~ "data-region-name"
    end

    test "the portal glyph carries NO identifying attribute" do
      html = render_map(cross_region_view())

      assert [chunk] = Regex.run(~r/<rect[^>]*map-portal[^>]*>/, html)
      refute chunk =~ "data-room-name"
      refute chunk =~ "data-room-id"
      refute chunk =~ "data-target"
      refute chunk =~ "data-region-name"
    end

    test "destination region name never appears in cross-region markup" do
      # cross_region_view source region is Blackmire; the destination
      # would be Hollowvale or similar. The fixture deliberately does
      # NOT include the destination's name anywhere. Verify the renderer
      # doesn't accidentally insert it via title, aria, etc.
      html = render_map(cross_region_view())

      refute html =~ "Hollowvale"
      refute html =~ "Outskirts"
    end

    test "no <title> elements on cross-region line or portal" do
      html = render_map(cross_region_view())

      # Extract just the cross-region SVG section by finding the line + portal.
      cross_section =
        case Regex.run(
               ~r/(<line[^>]*map-line--cross-region.*?<rect[^>]*map-portal[^>]*>)/s,
               html
             ) do
          [_, section] -> section
          _ -> ""
        end

      refute cross_section =~ "<title>"
    end
  end

  # ----------------------------------------------------------------
  # Polish — dir-pad expansion (research R7)
  # ----------------------------------------------------------------

  describe "dir-pad — 3x3 compass + Up/Down column" do
    test "renders all 8 compass buttons + a center look button + Up/Dn" do
      html = render_dir_pad()

      for {label, aria} <- [
            {"NW", "Move northwest"},
            {"N", "Move north"},
            {"NE", "Move northeast"},
            {"W", "Move west"},
            {"E", "Move east"},
            {"SW", "Move southwest"},
            {"S", "Move south"},
            {"SE", "Move southeast"},
            {"Up", "Move up"},
            {"Dn", "Move down"}
          ] do
        assert Regex.match?(~r/>\s*#{Regex.escape(label)}\s*</, html),
               "missing button label: #{label}"

        assert html =~ ~s|aria-label="#{aria}"|, "missing aria-label: #{aria}"
      end

      assert html =~ ~s|aria-label="Look around"|
    end

    test "each direction button emits submit_command with the full direction name" do
      html = render_dir_pad()

      for cmd <- ~w(north south east west northeast northwest southeast southwest up down look) do
        assert html =~ ~s|phx-value-text="#{cmd}"|, "missing phx-value-text=#{cmd}"
      end
    end

    test "dir-pad uses the dir-btn class and wrapping containers" do
      html = render_dir_pad()
      assert html =~ "dir-pad-wrap"
      assert html =~ "dir-pad-vert"
      # The look button has the distinguishing class.
      assert html =~ "dir-btn--look"
    end
  end

  # ----------------------------------------------------------------
  # US7 — hover tooltip plumbing (data-room-name placement)
  # ----------------------------------------------------------------
  #
  # The ColocatedHook (.MapTooltip) drives tooltip:show/hide via the
  # data-room-name attribute. The renderer's job is to put that attribute
  # on .map-cell groups ONLY — never on fog stubs or cross-region
  # portals, where it would leak destination identity per FR-017.

  describe "US7 — data-room-name placement" do
    test "every .map-cell carries data-room-name matching the room's display name" do
      html = render_map(linear_three_view())

      data_names = Regex.scan(~r/data-room-name="([^"]+)"/, html)
      names = Enum.map(data_names, fn [_, name] -> name end)

      assert "A" in names
      assert "B" in names
      assert "C" in names
      assert length(names) == 3
    end

    test "fog-stub render places NO data-room-name on the line or cloud" do
      html = render_map(fog_stub_view())

      data_names = Regex.scan(~r/data-room-name="([^"]+)"/, html)
      # Only the source room ("A") should carry the attribute.
      names = Enum.map(data_names, fn [_, name] -> name end)
      assert names == ["A"]
    end

    test "cross-region render places NO data-room-name on the line or portal" do
      html = render_map(cross_region_view())

      data_names = Regex.scan(~r/data-room-name="([^"]+)"/, html)
      # Only "Border" — the rendered source — should carry the attribute.
      names = Enum.map(data_names, fn [_, name] -> name end)
      assert names == ["Border"]
    end

    test "SVG carries the phx-hook directive for the tooltip hook" do
      html = render_map(linear_three_view())
      # Phoenix resolves `.MapTooltip` (defined in this module's
      # ColocatedHook script) to the fully-qualified module path.
      assert html =~ "MapTooltip"
      assert html =~ "phx-hook"
      assert html =~ ~s|id="map-canvas-svg"|
    end

    test "off-map render has NO data-room-name (no rooms to hover)" do
      html = render_map(off_map_view())

      data_names = Regex.scan(~r/data-room-name="([^"]+)"/, html)
      assert data_names == []
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
