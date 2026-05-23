# Contract: `SpawnNPC` Command + `Room` Aggregate Handler

## Command struct

`AgenticRealms.World.Commands.SpawnNPC`

| Field               | Type        | Required | Notes                                            |
|---------------------|-------------|----------|--------------------------------------------------|
| `room_id`           | `binary_id` | yes      | Existing room (`world_rooms.id`).                 |
| `npc_id`            | `binary_id` | yes      | Globally unique. Caller (seed) supplies.          |
| `name`              | `string`    | yes      | Display name. Per-room unique.                    |
| `short_description` | `string`    | yes      | Non-empty.                                        |
| `long_description`  | `string`    | yes      | Non-empty (FR-001).                               |

Routing: registered on `World.Router` to `Room` aggregate. Aggregate key is `:room_id` with prefix `"room-"` (matches existing room commands).

## Aggregate handler — happy path

```elixir
def execute(%__MODULE__{id: rid, npc_ids: ids, npc_names_lower: names}, %SpawnNPC{
      room_id: rid,
      npc_id: nid,
      name: name,
      short_description: short,
      long_description: long
    }) do
  cond do
    MapSet.member?(ids, nid) ->
      {:error, :npc_already_in_room}

    MapSet.member?(names, String.downcase(name)) ->
      {:error, :npc_name_taken_in_room}

    short in [nil, ""] ->
      {:error, :short_description_required}

    long in [nil, ""] ->
      {:error, :long_description_required}

    true ->
      %NPCSpawnedInRoom{
        room_id: rid,
        npc_id: nid,
        name: name,
        short_description: short,
        long_description: long
      }
  end
end

def execute(%__MODULE__{id: nil}, %SpawnNPC{}), do: {:error, :room_not_found}
```

## Aggregate handler — apply/2

```elixir
def apply(
      %__MODULE__{npc_ids: ids, npc_names_lower: names} = state,
      %NPCSpawnedInRoom{npc_id: nid, name: name}
    ) do
  %__MODULE__{
    state
    | npc_ids: MapSet.put(ids, nid),
      npc_names_lower: MapSet.put(names, String.downcase(name))
  }
end
```

## Error contract

| Error atom                       | Cause                                                  | Caller behavior                                   |
|----------------------------------|--------------------------------------------------------|---------------------------------------------------|
| `:room_not_found`                | Aggregate state has no room (id == nil).                | Caller (seed) logs and aborts.                    |
| `:npc_already_in_room`           | `npc_id` already in `npc_ids`.                          | Idempotent re-seed: caller treats as "already done"; otherwise an authoring bug.   |
| `:npc_name_taken_in_room`        | Per-room name uniqueness violation (FR-001a).           | Authoring bug. Seed aborts.                       |
| `:short_description_required`    | Empty/nil `short_description`.                          | Authoring bug. Seed aborts.                       |
| `:long_description_required`     | Empty/nil `long_description`.                           | Authoring bug. Seed aborts.                       |

## Router change

In `lib/agenticrealms/world/router.ex`:

```elixir
alias AgenticRealms.World.Commands.{
  CreateRoom,
  AddExit,
  PlaceObject,
  SpawnPlayer,
  MovePlayer,
  TakeObject,
  DropObject,
  SpawnNPC          # NEW
}

dispatch([CreateRoom, AddExit, PlaceObject, TakeObject, DropObject, SpawnNPC], to: Room)
```

## Caller contract: seed

`Seed.run/0`'s `do_seed` is extended with one `SpawnNPC` dispatch after the three `PlaceObject` calls:

```elixir
:ok =
  WorldApp.dispatch(%SpawnNPC{
    room_id: @starting_room_id,
    npc_id: @innkeeper_garrick_id,    # NEW module attribute: stable UUID
    name: "Garrick the Innkeeper",
    short_description: "a wiry innkeeper in a stained apron",
    long_description:
      "A wiry man in a stained apron, his hands callused and his eyes patient. He polishes a tankard that already looks clean and watches the door without quite seeming to."
  })
```

The `@innkeeper_garrick_id` UUID is pinned (consistent with all existing seed entity IDs) so re-runs are idempotent against the existing seed-skipping check (`Repo.aggregate(Room, :count) > 0`).
