# Contract: Region aggregate + CreateRegion / RegionCreated

## Module: `AgenticRealms.World.Region`

A Commanded aggregate that owns the lifecycle of a Region. v1 supports creation only.

### State

```elixir
defstruct id: nil, name: nil
```

### Commands handled

#### `CreateRegion`

```elixir
defmodule AgenticRealms.World.Commands.CreateRegion do
  @enforce_keys [:region_id, :name]
  defstruct [:region_id, :name]
end
```

**Validation** (in `Region.execute/2`):
- Aggregate state `id` MUST be `nil` (region not yet created). Otherwise → `{:error, :region_already_exists}`.
- `name` MUST be a non-empty string. (Trim + non-empty check in the aggregate; the command struct does not enforce this.)

**Emits**: `RegionCreated{region_id, name}`.

**Pre-dispatch wrapper** in `AgenticRealms.World.Commands` (new function `create_region/2`):
- Verify `name` is not already in use (DB unique-name check against the read model). Returns `{:error, :region_name_taken}` early instead of waiting for a DB error after dispatch.
- Dispatches with `consistency: :strong` so the seed and subsequent `CreateRoom` commands see the new region in the read model immediately.

### Events emitted

#### `RegionCreated`

```elixir
defmodule AgenticRealms.World.Events.RegionCreated do
  @derive Jason.Encoder
  @enforce_keys [:region_id, :name]
  defstruct [:region_id, :name, version: 1]
end
```

### Apply (replay)

```elixir
def apply(%__MODULE__{} = state, %RegionCreated{region_id: id, name: name}) do
  %__MODULE__{state | id: id, name: name}
end
```

### Router registration

Add to `AgenticRealms.World.Application` (the Commanded application's router config):

```elixir
identify(AgenticRealms.World.Region, by: :region_id)
dispatch [AgenticRealms.World.Commands.CreateRegion], to: AgenticRealms.World.Region
```

### Projection

`AgenticRealms.World.Projections.WorldProjector.handle/2` gains a clause:

```elixir
def handle(%RegionCreated{region_id: id, name: name}, _meta) do
  Repo.insert!(
    %Region{id: id, name: name},
    on_conflict: :nothing,
    conflict_target: :id
  )
  :ok
end
```

### Concurrency / replay properties

- Idempotent under replay (insert with `on_conflict: :nothing`).
- Idempotent under crashed-mid-dispatch: re-creating the same `region_id` returns `{:error, :region_already_exists}` from the aggregate, never duplicates the row.

### Out of scope

- Rename, delete, region-level metadata (description, theme). Future features.
