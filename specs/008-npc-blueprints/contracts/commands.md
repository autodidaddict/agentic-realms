# Contract: `CreateNPCBlueprint` + `SpawnNPCClone` + `World.NPCBlueprint` Aggregate

## Aggregate

`AgenticRealms.World.NPCBlueprint`. Identified by `:blueprint_id` with prefix `"npc-blueprint-"`. Registered on `World.Router`:

```elixir
identify(NPCBlueprint, by: :blueprint_id, prefix: "npc-blueprint-")
dispatch([CreateNPCBlueprint, SpawnNPCClone], to: NPCBlueprint)
```

## Command: `CreateNPCBlueprint`

```elixir
defmodule AgenticRealms.World.Commands.CreateNPCBlueprint do
  @enforce_keys [:blueprint_id, :name, :short_description, :long_description]
  defstruct [:blueprint_id, :name, :short_description, :long_description]
end
```

| Field               | Type     | Required | Notes                                                  |
|---------------------|----------|----------|--------------------------------------------------------|
| `blueprint_id`      | `string` | yes      | Slug. Globally unique. Caller (seed) supplies.         |
| `name`              | `string` | yes      | Display name. Non-empty.                               |
| `short_description` | `string` | yes      | Non-empty.                                             |
| `long_description`  | `string` | yes      | Non-empty (FR-004).                                    |

### Aggregate handler

```elixir
def execute(%__MODULE__{id: nil}, %CreateNPCBlueprint{
      blueprint_id: bp_id,
      name: name,
      short_description: short,
      long_description: long
    }) do
  cond do
    name in [nil, ""] -> {:error, :name_required}
    short in [nil, ""] -> {:error, :short_description_required}
    long in [nil, ""] -> {:error, :long_description_required}
    true ->
      %NPCBlueprintCreated{
        blueprint_id: bp_id,
        name: name,
        short_description: short,
        long_description: long
      }
  end
end

def execute(%__MODULE__{}, %CreateNPCBlueprint{}),
  do: {:error, :blueprint_already_exists}
```

### Error contract

| Error atom                       | Cause                                  | Caller behavior                              |
|----------------------------------|----------------------------------------|----------------------------------------------|
| `:blueprint_already_exists`      | Aggregate has been initialized.        | Seed treats as idempotent re-run; otherwise an authoring bug. |
| `:name_required`                 | Empty/nil name.                        | Authoring bug. Seed aborts.                  |
| `:short_description_required`    | Empty/nil short description.           | Authoring bug. Seed aborts.                  |
| `:long_description_required`     | Empty/nil long description (FR-004).   | Authoring bug. Seed aborts.                  |

## Command: `SpawnNPCClone`

```elixir
defmodule AgenticRealms.World.Commands.SpawnNPCClone do
  @enforce_keys [:blueprint_id, :clone_id, :room_id]
  defstruct [:blueprint_id, :clone_id, :room_id]
end
```

| Field          | Type        | Required | Notes                                                            |
|----------------|-------------|----------|------------------------------------------------------------------|
| `blueprint_id` | `string`    | yes      | Existing blueprint identifier.                                   |
| `clone_id`     | `binary_id` | yes      | Globally unique UUID. Caller supplies (seed pins; tests generate). |
| `room_id`      | `binary_id` | yes      | Destination room. Must exist (validated pre-dispatch).            |

### Aggregate handler

The aggregate stamps its CURRENT state into the emitted event — this is the full-copy materialization point (I-3, FR-007).

```elixir
def execute(%__MODULE__{id: nil}, %SpawnNPCClone{}),
  do: {:error, :blueprint_not_found}

def execute(
      %__MODULE__{
        id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        next_serial: serial,
        clone_ids: clones
      },
      %SpawnNPCClone{blueprint_id: bp_id, clone_id: cid, room_id: rid}
    ) do
  if MapSet.member?(clones, cid) do
    {:error, :clone_id_already_used}
  else
    %NPCClonedFromBlueprint{
      blueprint_id: bp_id,
      clone_id: cid,
      room_id: rid,
      serial: serial,
      name: name,
      short_description: short,
      long_description: long
    }
  end
end
```

### apply/2

```elixir
def apply(%__MODULE__{} = state, %NPCBlueprintCreated{
      blueprint_id: bp_id,
      name: name,
      short_description: short,
      long_description: long
    }) do
  %__MODULE__{
    state
    | id: bp_id,
      name: name,
      short_description: short,
      long_description: long
  }
end

def apply(
      %__MODULE__{next_serial: s, clone_ids: c} = state,
      %NPCClonedFromBlueprint{clone_id: cid}
    ) do
  %__MODULE__{state | next_serial: s + 1, clone_ids: MapSet.put(c, cid)}
end
```

### Error contract

| Error atom                       | Cause                                                     | Caller behavior                                   |
|----------------------------------|-----------------------------------------------------------|---------------------------------------------------|
| `:blueprint_not_found`           | `blueprint_id` not yet initialized in the aggregate.       | Caller aborts; surfaces as `World.Commands.spawn_npc_clone/3` pre-dispatch error. |
| `:clone_id_already_used`         | The supplied `clone_id` was already issued by this aggregate. | Caller bug. Tests catch.                          |

## Pre-dispatch wrapper: `World.Commands.spawn_npc_clone/3`

```elixir
@spec spawn_npc_clone(String.t(), String.t(), String.t()) ::
        {:ok, %{clone_id: String.t(), serial: integer()}}
        | {:error, atom()}
def spawn_npc_clone(blueprint_id, room_id, clone_id)
    when is_binary(blueprint_id) and is_binary(room_id) and is_binary(clone_id) do
  with {:ok, blueprint} <- Queries.get_npc_blueprint(blueprint_id),
       :ok <- check_room_exists(room_id),
       :ok <- check_no_clone_name_collision(room_id, blueprint.name),
       :ok <-
         WorldApp.dispatch(
           %SpawnNPCClone{
             blueprint_id: blueprint_id,
             clone_id: clone_id,
             room_id: room_id
           },
           consistency: :strong
         ) do
    # Re-query the freshly-projected clone to return its serial.
    {:ok, clone} = Queries.get_npc_clone(clone_id)
    {:ok, %{clone_id: clone_id, serial: clone.serial}}
  end
end

defp check_room_exists(room_id) do
  case Repo.get(Schemas.Room, room_id) do
    %Schemas.Room{} -> :ok
    nil -> {:error, :room_not_found}
  end
end

defp check_no_clone_name_collision(room_id, name) do
  case Queries.find_clone_in_room_by_name(room_id, name) do
    {:ok, _clone} -> {:error, :clone_name_taken_in_room}
    {:error, :no_such_clone} -> :ok
  end
end
```

### Wrapper error contract

| Error atom                       | Cause                                                  | LiveView behavior (future) |
|----------------------------------|--------------------------------------------------------|----------------------------|
| `:blueprint_not_found`           | Blueprint with the given id has not been authored.     | Seed/test failure.         |
| `:room_not_found`                | Room with the given id does not exist.                 | Seed/test failure.         |
| `:clone_name_taken_in_room`      | Another clone with the same display name is already in this room (FR-015). | Authoring failure.         |
| `:clone_id_already_used`         | (Aggregate) the supplied clone_id is already issued.   | Test/seed bug.             |

## Caller contract: seed

`Seed.do_seed/0` after the existing room / exit / object dispatches:

```elixir
# Garrick — feature 008 blueprint + clone (replaces feature 007's SpawnNPC dispatch)
:ok =
  WorldApp.dispatch(%CreateNPCBlueprint{
    blueprint_id: "garrick_the_innkeeper",
    name: "Garrick the Innkeeper",
    short_description: "a wiry innkeeper in a stained apron",
    long_description:
      "A wiry man in a stained apron, his hands callused and his eyes patient. He polishes a tankard that already looks clean and watches the door without quite seeming to."
  })

{:ok, _} =
  Commands.spawn_npc_clone(
    "garrick_the_innkeeper",
    @starting_room_id,
    @innkeeper_garrick_clone_id
  )
```

The pinned UUID `@innkeeper_garrick_clone_id` is the same UUID as feature 007's `@innkeeper_garrick_id` — preserved verbatim for continuity (any tests that hardcoded the UUID continue to work).
