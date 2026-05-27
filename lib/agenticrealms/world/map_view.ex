defmodule AgenticRealms.World.MapView do
  @moduledoc """
  Read-model projection of "what does this player see on the map right now."

  This module is a pure DB query + struct-assembly layer. It is invoked by
  `AgenticRealmsWeb.GameLive` on mount and on every `PlayerCurrentRoomChanged`
  event. Performance matters: `for_player/1` completes in single-digit
  milliseconds on realistic data, dominated by 3–5 indexed Postgres queries
  bounded by the viewport size.

  Feature 012 — Maps. See `specs/012-maps/contracts/map-view.md`.

  ## Information-hiding contract

  The renderer trusts MapView to be honest about what's visible. MapView
  MUST NOT emit destination room ids/names/region-ids on `:fog_stub` or
  `:cross_region` exit entries (FR-007, FR-008, FR-017). The struct shapes
  below are deliberately narrow to make leaks impossible.

  ## Off-map state

  When the player's current room is map-hidden OR has no coordinates set,
  `for_player/1` returns a struct with `off_map?: true` and empty room/exit
  lists. The renderer detects this and draws only the region-name header.
  """

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Direction.Geometry
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.{Region, Room, Exit, PlayerState}

  defstruct region_id: nil,
            region_name: nil,
            current_room_id: nil,
            off_map?: false,
            viewport_center: {0, 0},
            rooms: [],
            exits: [],
            has_above_rooms?: false,
            has_below_rooms?: false

  defmodule RoomGlyph do
    @moduledoc """
    A room glyph to render. Carries only what the renderer needs.
    """
    defstruct [:id, :name, :x, :y, :is_current?, :has_up?, :has_down?]
  end

  defmodule ExitLine do
    @moduledoc """
    A line to draw between two screen positions. `kind` selects the renderer
    branch (`:normal` line vs. `:fog_stub` vs. `:cross_region` affordance).
    """
    defstruct [:kind, :from_x, :from_y, :to_x, :to_y, :direction]
  end

  @doc """
  Build the per-player MapView. Reads `viewport_cells` from app config
  (default 11). Returns a fully-populated `%MapView{}` even when the player
  is off-map (the renderer branches on `off_map?`).
  """
  @spec for_player(integer()) :: %__MODULE__{}
  def for_player(player_id) when is_integer(player_id) do
    case Queries.current_room_of(player_id) do
      {:error, :no_current_room} ->
        empty_view()

      {:ok, current_room_id} ->
        case Repo.get(Room, current_room_id) do
          nil ->
            empty_view()

          %Room{region_id: nil} = current ->
            current_only_view(current)

          %Room{} = current ->
            region = Repo.get(Region, current.region_id)
            do_build(player_id, current, region)
        end
    end
  end

  @doc """
  Default initial zoom level in cells (the SVG viewBox is `default_zoom_cells`
  cells wide and tall, centered on the player's current room). Mouse-wheel
  zoom and click-drag pan are owned by the client-side `.MapInteract` hook
  — the server never re-renders for pan/zoom interactions.
  """
  @spec default_zoom_cells() :: pos_integer()
  def default_zoom_cells do
    Application.get_env(:agenticrealms, AgenticRealms.MapRenderer, [])
    |> Keyword.get(:default_zoom_cells, 3)
  end

  # ------------------------------------------------------------------------
  # Build pipeline
  # ------------------------------------------------------------------------

  defp empty_view do
    %__MODULE__{
      region_id: nil,
      region_name: nil,
      current_room_id: nil,
      off_map?: true
    }
  end

  defp current_only_view(%Room{id: id}) do
    %__MODULE__{
      region_id: nil,
      region_name: nil,
      current_room_id: id,
      off_map?: true
    }
  end

  defp do_build(_player_id, current, nil), do: current_only_view(current)

  defp do_build(player_id, %Room{} = current, %Region{} = region) do
    if off_map_room?(current) do
      off_map_view(current, region)
    else
      normal_view(player_id, current, region)
    end
  end

  defp off_map_room?(%Room{map_visible: false}), do: true
  defp off_map_room?(%Room{map_x: nil}), do: true
  defp off_map_room?(%Room{map_y: nil}), do: true
  defp off_map_room?(_), do: false

  defp off_map_view(%Room{id: id}, %Region{id: region_id, name: region_name}) do
    %__MODULE__{
      region_id: region_id,
      region_name: region_name,
      current_room_id: id,
      off_map?: true,
      viewport_center: {0, 0},
      rooms: [],
      exits: [],
      has_above_rooms?: false,
      has_below_rooms?: false
    }
  end

  # Hot path. Four indexed queries (discovery + rooms + exits + two
  # short-circuit EXISTS for above/below). The server emits ALL discovered
  # rooms in the current region+elevation — the client owns viewport
  # decisions via SVG viewBox pan/zoom.
  defp normal_view(player_id, %Room{} = current, %Region{} = region) do
    # The current room is trivially "discovered" — the player is standing
    # in it. Add it unconditionally so the renderer can draw the "you are
    # here" highlight immediately on first spawn, even before the
    # eventually-consistent PlayerDiscoveredRoom row lands in the read
    # model.
    discovered =
      player_id
      |> Queries.discovered_room_ids_for()
      |> MapSet.put(current.id)

    rendered_rooms =
      Queries.rooms_in_region_at_elevation(region.id, current.elevation, discovered)

    rendered_by_id = Map.new(rendered_rooms, &{&1.id, &1})
    rendered_id_set = MapSet.new(Map.keys(rendered_by_id))

    exits = Queries.exits_for_rooms(Enum.map(rendered_rooms, & &1.id))

    {has_up, has_down} = vertical_icon_sets(exits)

    glyphs =
      Enum.map(rendered_rooms, fn r ->
        %RoomGlyph{
          id: r.id,
          name: r.name,
          x: r.map_x,
          y: r.map_y,
          is_current?: r.id == current.id,
          has_up?: MapSet.member?(has_up, r.id),
          has_down?: MapSet.member?(has_down, r.id)
        }
      end)

    exit_lines =
      build_exit_lines(
        exits,
        rendered_by_id,
        rendered_id_set,
        discovered
      )

    %__MODULE__{
      region_id: region.id,
      region_name: region.name,
      current_room_id: current.id,
      off_map?: false,
      viewport_center: {current.map_x, current.map_y},
      rooms: glyphs,
      exits: exit_lines,
      has_above_rooms?:
        Queries.has_discovered_rooms_above?(region.id, current.elevation, player_id),
      has_below_rooms?:
        Queries.has_discovered_rooms_below?(region.id, current.elevation, player_id)
    }
  end

  # ------------------------------------------------------------------------
  # Exit classification
  # ------------------------------------------------------------------------

  # Classifies each outgoing exit into one of:
  #   * `:normal`   — between two rendered rooms, deduped by unordered pair
  #   * `:fog_stub` — destination is map-visible + coord-set + UNDISCOVERED;
  #     a half-step line extends from the source toward the direction with
  #     NO destination identity carried through (FR-007 / FR-017)
  #
  # Suppressed entirely (no entry):
  #   * destination is map-hidden or has no coords (FR-006)
  #   * destination is in a different region (deferred to US6 :cross_region)
  #   * vertical exits (Up/Down) — those produce icons on the source room,
  #     not lines
  #   * destination is discovered + map-visible but OUTSIDE the rendered
  #     viewport window (off-screen — keep the renderer simple for v1)
  #
  # Dedup invariant (FR-004): exactly one line per unordered pair of
  # rendered rooms. Reciprocal exits (A→B + B→A) collapse to one line.
  # Fog stubs DO NOT dedupe — each undiscovered direction from the same
  # source room produces its own stub (they emerge in different
  # directions; the player needs to see each).
  defp build_exit_lines(exits, rendered_by_id, rendered_id_set, discovered) do
    # `normal_lines` is a map keyed on the unordered pair {a, b} so
    # reciprocal exits collapse to one entry (FR-004). `other_lines`
    # holds fog stubs and cross-region affordances — both are non-
    # dedupable (each direction-from-source carries its own meaning).
    {normal_lines, other_lines} =
      Enum.reduce(exits, {%{}, []}, fn %Exit{} = e, {normal_acc, other_acc} ->
        direction = direction_atom(e.direction)

        cond do
          # Vertical exits produce icons, not lines.
          direction in [:up, :down] ->
            {normal_acc, other_acc}

          # FR-006: a map-hidden room (or one without coords) leaves NO
          # visible trace on the map. The source-side line is suppressed
          # entirely — no :normal, no :fog_stub, no :cross_region affordance.
          # The source room looks identical to one with no exit in that
          # direction. This is the wizard's primary tool for secret areas.
          is_nil(e.target_room) or e.target_room.map_visible != true or
            is_nil(e.target_room.map_x) or is_nil(e.target_room.map_y) ->
            {normal_acc, other_acc}

          # FR-008 — cross-region exit. Source is rendered; target is in
          # a DIFFERENT region. The destination room is NOT drawn on this
          # view (regions are independent map planes); we emit a
          # :cross_region affordance whose endpoint sits ~0.85 cells into
          # the direction from the source — slightly further out than a
          # fog stub so the portal glyph has clear visual separation from
          # the source room's rect edge (at ±0.43 cells) and the current-
          # room glow. NO destination identity carried.
          e.target_room.region_id != Map.fetch!(rendered_by_id, e.source_room_id).region_id ->
            source = Map.fetch!(rendered_by_id, e.source_room_id)
            {dx, dy} = Geometry.unit_vector(direction)

            cross = %ExitLine{
              kind: :cross_region,
              from_x: source.map_x,
              from_y: source.map_y,
              to_x: source.map_x + dx * 0.85,
              to_y: source.map_y + dy * 0.85,
              direction: direction
            }

            {normal_acc, [cross | other_acc]}

          # Both endpoints rendered → :normal (dedup by unordered pair).
          MapSet.member?(rendered_id_set, e.target_room.id) ->
            a = e.source_room_id
            b = e.target_room.id
            key = canonical_pair(a, b)

            if Map.has_key?(normal_acc, key) do
              {normal_acc, other_acc}
            else
              source = Map.fetch!(rendered_by_id, a)

              line = %ExitLine{
                kind: :normal,
                from_x: source.map_x,
                from_y: source.map_y,
                to_x: e.target_room.map_x,
                to_y: e.target_room.map_y,
                direction: direction
              }

              {Map.put(normal_acc, key, line), other_acc}
            end

          # Target undiscovered but map-visible + coord-set → :fog_stub.
          not MapSet.member?(discovered, e.target_room.id) ->
            source = Map.fetch!(rendered_by_id, e.source_room_id)
            {dx, dy} = Geometry.unit_vector(direction)
            # Stub extends ~0.6 cells beyond the source room's center —
            # short enough to feel like a teaser, long enough to read.
            stub = %ExitLine{
              kind: :fog_stub,
              from_x: source.map_x,
              from_y: source.map_y,
              # Float endpoints render fine in SVG; the cell-to-pixel
              # transform in the renderer multiplies by cell_size_px.
              to_x: source.map_x + dx * 0.6,
              to_y: source.map_y + dy * 0.6,
              direction: direction
            }

            {normal_acc, [stub | other_acc]}

          # Discovered + map-visible + coord-set but outside the rendered
          # viewport (room exists but the player has wandered past the
          # window) → suppress (off-screen affordance is out of scope).
          true ->
            {normal_acc, other_acc}
        end
      end)

    Map.values(normal_lines) ++ Enum.reverse(other_lines)
  end

  defp canonical_pair(a, b) when a <= b, do: {a, b}
  defp canonical_pair(a, b), do: {b, a}

  defp direction_atom(s) when is_binary(s), do: String.to_existing_atom(s)
  defp direction_atom(a) when is_atom(a), do: a

  # ------------------------------------------------------------------------
  # Up/Down icon sets
  # ------------------------------------------------------------------------

  defp vertical_icon_sets(exits) do
    Enum.reduce(exits, {MapSet.new(), MapSet.new()}, fn %Exit{} = e, {up_set, down_set} ->
      cond do
        not renderable_vertical_target?(e.target_room) ->
          {up_set, down_set}

        e.direction == "up" ->
          {MapSet.put(up_set, e.source_room_id), down_set}

        e.direction == "down" ->
          {up_set, MapSet.put(down_set, e.source_room_id)}

        true ->
          {up_set, down_set}
      end
    end)
  end

  defp renderable_vertical_target?(%Room{map_visible: true, map_x: x, map_y: y})
       when not is_nil(x) and not is_nil(y),
       do: true

  defp renderable_vertical_target?(_), do: false

  # PlayerState is preloaded by the LiveView via Queries.current_room_of/1;
  # the alias is kept here for future use (incremental MapView updates
  # might key off PlayerState rows directly).
  _ = PlayerState
end
