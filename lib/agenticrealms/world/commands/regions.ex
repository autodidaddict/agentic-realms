defmodule AgenticRealms.World.Commands.Regions do
  @moduledoc """
  Write-side facade for world authoring (feature 012): regions, rooms, and the
  exits between them.

  Split out of `AgenticRealms.World.Commands`, which had grown to cover every
  bounded concern in the world behind one module. `Commands` still delegates
  here, so callers are unchanged.
  """

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.Commands.{AddExit, CreateRegion, CreateRoom}
  alias AgenticRealms.World.Exits.Validator, as: ExitsValidator
  alias AgenticRealms.World.Schemas.{Region, Room}

  # --- Region authoring (feature 012) -------------------------------------

  @doc """
  Create a new region with the given `region_id` and friendly display
  `name`. Pre-dispatch validation: the name is not already in use in the
  read model.

  Dispatches with `consistency: :strong` so the seed (and any subsequent
  `CreateRoom` referencing the new region) can rely on the read-model row
  being present immediately after this returns.
  """
  @spec create_region(String.t(), String.t()) ::
          :ok | {:error, :region_name_taken | term()}
  def create_region(region_id, name) when is_binary(region_id) and is_binary(name) do
    with :ok <- check_region_name_unique(name) do
      WorldApp.dispatch(
        %CreateRegion{region_id: region_id, name: name},
        consistency: :strong
      )
    end
  end

  defp check_region_name_unique(name) do
    case Repo.one(from(r in Region, where: r.name == ^name, select: r.id, limit: 1)) do
      nil -> :ok
      _ -> {:error, :region_name_taken}
    end
  end

  # --- Room authoring (feature 012) ---------------------------------------

  @doc """
  Create a room with map metadata. `opts` may include `:behaviors` (default
  `[]`), `:map_visible` (default `true`), `:elevation` (default `0`),
  `:map_x` and `:map_y` (both default `nil`, meaning off-map).

  Pre-dispatch validation:
    * region exists in the read model (`:region_not_found`)
    * `(:map_x, :map_y)` are both nil OR both integers (`:coords_must_be_pair`)
    * if coords are set, no existing room at `(region_id, elevation, map_x, map_y)`
      (`:coord_taken` — anticipates the partial unique index with a friendly error)
    * elevation is an integer
  """
  @spec create_room(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          :ok
          | {:error,
             :region_not_found
             | :coords_must_be_pair
             | :coord_taken
             | :elevation_must_be_integer
             | term()}
  def create_room(room_id, name, description, region_id, opts \\ [])
      when is_binary(room_id) and is_binary(name) and is_binary(description) and
             is_binary(region_id) do
    behaviors = Keyword.get(opts, :behaviors, [])
    map_visible = Keyword.get(opts, :map_visible, true)
    elevation = Keyword.get(opts, :elevation, 0)
    map_x = Keyword.get(opts, :map_x)
    map_y = Keyword.get(opts, :map_y)

    with :ok <- check_region_exists(region_id),
         :ok <- check_coords_pair(map_x, map_y),
         :ok <- check_elevation_integer(elevation),
         :ok <- check_coord_not_taken(region_id, elevation, map_x, map_y) do
      WorldApp.dispatch(
        %CreateRoom{
          room_id: room_id,
          name: name,
          description: description,
          region_id: region_id,
          behaviors: behaviors,
          map_visible: map_visible,
          elevation: elevation,
          map_x: map_x,
          map_y: map_y
        },
        consistency: :strong
      )
    end
  end

  @doc """
  Add a directional exit from `source_room_id` to `target_room_id`.
  Validates direction-coordinate consistency per FR-024 via
  `Exits.Validator`. Off-map rooms (either side missing coords) skip the
  geometric check — supports wormhole-like patterns.
  """
  @spec add_exit(String.t(), atom(), String.t()) ::
          :ok
          | {:error,
             :source_room_not_found
             | :target_room_not_found
             | {:exit_geometry_violation, atom()}
             | term()}
  def add_exit(source_room_id, direction, target_room_id)
      when is_binary(source_room_id) and is_atom(direction) and is_binary(target_room_id) do
    with {:ok, source} <- fetch_room(source_room_id, :source_room_not_found),
         {:ok, target} <- fetch_room(target_room_id, :target_room_not_found),
         :ok <- ExitsValidator.consistent?(direction, source, target) do
      WorldApp.dispatch(%AddExit{
        room_id: source_room_id,
        direction: direction,
        target_room_id: target_room_id
      })
    end
  end

  defp check_region_exists(region_id) do
    case Repo.one(from(r in Region, where: r.id == ^region_id, select: r.id, limit: 1)) do
      nil -> {:error, :region_not_found}
      _ -> :ok
    end
  end

  defp check_coords_pair(nil, nil), do: :ok
  defp check_coords_pair(x, y) when is_integer(x) and is_integer(y), do: :ok
  defp check_coords_pair(_, _), do: {:error, :coords_must_be_pair}

  defp check_elevation_integer(e) when is_integer(e), do: :ok
  defp check_elevation_integer(_), do: {:error, :elevation_must_be_integer}

  defp check_coord_not_taken(_region_id, _elevation, nil, nil), do: :ok

  defp check_coord_not_taken(region_id, elevation, map_x, map_y) do
    existing =
      Repo.one(
        from(r in Room,
          where:
            r.region_id == ^region_id and
              r.elevation == ^elevation and
              r.map_x == ^map_x and
              r.map_y == ^map_y,
          select: r.id,
          limit: 1
        )
      )

    case existing do
      nil -> :ok
      _ -> {:error, :coord_taken}
    end
  end

  defp fetch_room(room_id, missing_error) do
    case Repo.get(Room, room_id) do
      %Room{} = r -> {:ok, r}
      nil -> {:error, missing_error}
    end
  end
end
