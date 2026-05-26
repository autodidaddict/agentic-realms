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
  Returns `viewport_cells` from app config (default 11 — odd so the player
  sits in the center cell of the rendered window).
  """
  @spec viewport_cells() :: pos_integer()
  def viewport_cells do
    Application.get_env(:agenticrealms, AgenticRealms.MapRenderer, [])
    |> Keyword.get(:viewport_cells, 11)
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

  # Hot path. Five indexed queries, all bounded by the viewport size or by
  # short-circuit EXISTS. Avoid adding work here without measuring.
  defp normal_view(player_id, %Room{} = current, %Region{} = region) do
    # The current room is trivially "discovered" — the player is standing
    # in it. We add it to the set unconditionally so the renderer can draw
    # the "you are here" highlight immediately on first spawn, even before
    # the eventually-consistent PlayerDiscoveredRoom row lands in the read
    # model (the projector dispatches the discovery from inside its own
    # event handler, so the row arrives asynchronously).
    discovered =
      player_id
      |> Queries.discovered_room_ids_for()
      |> MapSet.put(current.id)

    viewport = viewport_cells()
    center = {current.map_x, current.map_y}

    rendered_rooms =
      Queries.rooms_in_region_at_elevation_within_viewport(
        region.id,
        current.elevation,
        center,
        viewport,
        discovered
      )

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

    exit_lines = build_normal_exit_lines(exits, rendered_by_id, rendered_id_set)

    %__MODULE__{
      region_id: region.id,
      region_name: region.name,
      current_room_id: current.id,
      off_map?: false,
      viewport_center: center,
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

  # For US1 we emit only `:normal` lines — between two rendered rooms.
  # `:fog_stub` (US3) and `:cross_region` (US6) extend this in later phases.
  #
  # Dedup invariant (FR-004): exactly one line per unordered pair of rooms.
  # Reciprocal exits (A→B + B→A) MUST NOT produce two overlapping lines.
  defp build_normal_exit_lines(exits, rendered_by_id, rendered_id_set) do
    exits
    |> Enum.filter(fn %Exit{target_room: t} ->
      not is_nil(t) and t.map_visible == true and not is_nil(t.map_x) and
        MapSet.member?(rendered_id_set, t.id)
    end)
    |> Enum.reduce({MapSet.new(), []}, fn %Exit{} = e, {seen, acc} ->
      a = e.source_room_id
      b = e.target_room.id
      key = canonical_pair(a, b)

      if MapSet.member?(seen, key) do
        {seen, acc}
      else
        source = Map.fetch!(rendered_by_id, a)

        line = %ExitLine{
          kind: :normal,
          from_x: source.map_x,
          from_y: source.map_y,
          to_x: e.target_room.map_x,
          to_y: e.target_room.map_y,
          direction: direction_atom(e.direction)
        }

        {MapSet.put(seen, key), [line | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
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
