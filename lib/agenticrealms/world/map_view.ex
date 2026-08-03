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
  `:cross_region` exit entries. The struct shapes
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

  defp normal_view(player_id, %Room{} = current, %Region{} = region) do
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

  defp build_exit_lines(exits, rendered_by_id, rendered_id_set, discovered) do
    {normal_lines, other_lines} =
      Enum.reduce(exits, {%{}, []}, fn %Exit{} = e, {normal_acc, other_acc} ->
        direction = direction_atom(e.direction)

        cond do
          direction in [:up, :down] ->
            {normal_acc, other_acc}

          is_nil(e.target_room) or e.target_room.map_visible != true or
            is_nil(e.target_room.map_x) or is_nil(e.target_room.map_y) ->
            {normal_acc, other_acc}

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

          not MapSet.member?(discovered, e.target_room.id) ->
            source = Map.fetch!(rendered_by_id, e.source_room_id)

            stub = %ExitLine{
              kind: :fog_stub,
              from_x: source.map_x,
              from_y: source.map_y,
              to_x: e.target_room.map_x,
              to_y: e.target_room.map_y,
              direction: direction
            }

            {normal_acc, [stub | other_acc]}

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

  _ = PlayerState
end
