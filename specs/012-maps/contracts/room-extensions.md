# Contract: Room command/event extensions

## `CreateRoom` extension

```elixir
defmodule AgenticRealms.World.Commands.CreateRoom do
  @enforce_keys [:room_id, :name, :description, :region_id]
  defstruct [
    :room_id, :name, :description, :region_id,
    behaviors: [],
    map_visible: true,
    elevation: 0,
    map_x: nil,
    map_y: nil
  ]
end
```

**Changes**: adds `:region_id` to `@enforce_keys`. Adds `map_visible`, `elevation`, `map_x`, `map_y` as optional fields with defaults.

### Pre-dispatch validation in `AgenticRealms.World.Commands.create_room/*`

1. Region exists in the read model (`Repo.exists?(from r in Region, where: r.id == ^region_id)`).
2. Coordinates: both nil OR both non-nil integers. Mixed (one set, one nil) is rejected with `{:error, :coords_must_be_pair}`.
3. If coords are set, no existing room with the same `(region_id, elevation, map_x, map_y)` (anticipates the DB partial unique constraint with a friendlier error message).
4. Elevation is an integer (no float, no string).

If any check fails, return the error tuple BEFORE dispatching to the aggregate.

### Aggregate `execute/2` extension in `AgenticRealms.World.Room`

```elixir
def execute(%__MODULE__{id: nil}, %CreateRoom{
      room_id: id,
      name: name,
      description: description,
      region_id: region_id,
      behaviors: behaviors,
      map_visible: map_visible,
      elevation: elevation,
      map_x: map_x,
      map_y: map_y
    }) do
  %RoomCreated{
    room_id: id,
    name: name,
    description: description,
    region_id: region_id,
    behaviors: behaviors,
    map_visible: map_visible,
    elevation: elevation,
    map_x: map_x,
    map_y: map_y
  }
end
```

### Aggregate `apply/2` extension

```elixir
def apply(%__MODULE__{} = state, %RoomCreated{
      room_id: id,
      name: name,
      description: description,
      region_id: region_id,
      behaviors: behaviors,
      map_visible: map_visible,
      elevation: elevation,
      map_x: map_x,
      map_y: map_y
    }) do
  %__MODULE__{
    state
    | id: id,
      name: name,
      description: description,
      region_id: region_id,
      behaviors: behaviors,
      map_visible: map_visible,
      elevation: elevation,
      map_x: map_x,
      map_y: map_y
  }
end
```

## `RoomCreated` event extension

```elixir
defmodule AgenticRealms.World.Events.RoomCreated do
  @derive Jason.Encoder
  @enforce_keys [:room_id, :name, :description, :region_id]
  defstruct [
    :room_id, :name, :description, :region_id,
    behaviors: [],
    map_visible: true,
    elevation: 0,
    map_x: nil,
    map_y: nil,
    version: 1
  ]
end
```

## Projector handler update

```elixir
def handle(
      %RoomCreated{
        room_id: id,
        name: name,
        description: description,
        region_id: region_id,
        behaviors: behaviors,
        map_visible: map_visible,
        elevation: elevation,
        map_x: map_x,
        map_y: map_y
      },
      _meta
    ) do
  Repo.insert!(
    %Room{
      id: id,
      name: name,
      description: description,
      behaviors: behaviors,
      region_id: region_id,
      map_visible: map_visible,
      elevation: elevation,
      map_x: map_x,
      map_y: map_y
    },
    on_conflict: :nothing,
    conflict_target: :id
  )
  :ok
end
```

## `AddExit` integration

`AgenticRealms.World.Commands.add_exit/3` (wrapper) is extended to call `Exits.Validator.consistent?/3` before dispatching:

```elixir
def add_exit(room_id, direction, target_room_id) do
  with {:ok, source} <- fetch_room(room_id),
       {:ok, target} <- fetch_room(target_room_id),
       :ok <- AgenticRealms.World.Exits.Validator.consistent?(direction, source, target) do
    WorldApp.dispatch(%AddExit{
      room_id: room_id,
      direction: direction,
      target_room_id: target_room_id
    })
  end
end
```

`fetch_room/1` returns `{:ok, %Room{}}` from the read model or `{:error, :room_not_found}`. The validator returns `:ok` or `{:error, {:exit_geometry_violation, reason}}` with a reason atom (see `contracts/exit-validator.md`).

The `AddExit` command struct itself is unchanged. The aggregate's existing exit-already-exists check (the `exits` map's `Map.has_key?/2` test) continues to enforce FR-spec uniqueness from feature 003.

## Backwards compatibility

Per FR-020b, all pre-feature-012 rooms are purged. There are no historical `RoomCreated` events without the new fields. The struct's `@enforce_keys` addition (`:region_id`) is therefore safe.

For paranoia: if a stale event without `:region_id` were ever encountered during replay, deserialization would fail loudly. This is the desired behavior — the migration paired with this feature ensures there are no such events.
