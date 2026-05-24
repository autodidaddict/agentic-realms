# Contract: `Queries` Module Changes

Behaviorally a no-op change from feature 007's perspective. The two NPC-related public functions are unchanged in signature and return shape; they just query a different table.

## Unchanged: `list_npcs_in_room/1` and `resolve_npc_in_room/2`

The same `@spec`, the same return value structure (`%{id, name, short_description}` for `list`; `{:ok, clone_id}` for `resolve`). The Ecto query targets `Schemas.NPCClone` instead of `Schemas.NPC`:

```elixir
alias AgenticRealms.World.Schemas.{Room, Exit, Object, PlayerState, NPCClone, NPCBlueprint}

@spec list_npcs_in_room(String.t()) ::
        [%{id: String.t(), name: String.t(), short_description: String.t()}]
def list_npcs_in_room(room_id) when is_binary(room_id) do
  from(c in NPCClone,
    where: c.room_id == ^room_id,
    order_by: c.name,
    select: %{id: c.id, name: c.name, short_description: c.short_description}
  )
  |> Repo.all()
end

@spec resolve_npc_in_room(String.t(), String.t()) ::
        {:ok, String.t()} | {:error, :no_such_npc | :ambiguous}
def resolve_npc_in_room(room_id, name) when is_binary(room_id) and is_binary(name) do
  needle = normalize_name(name)

  rows =
    from(c in NPCClone,
      where: c.room_id == ^room_id,
      select: %{id: c.id, name: c.name}
    )
    |> Repo.all()

  case Enum.filter(rows, fn r -> normalize_name(r.name) == needle end) do
    [] -> {:error, :no_such_npc}
    [%{id: id}] -> {:ok, id}
    _multiple -> {:error, :ambiguous}
  end
end
```

The alias block updates to add `NPCClone` and `NPCBlueprint`. The behavior is identical to feature 007's `Queries`.

## New: `get_npc_blueprint/1`

Supports the pre-dispatch check in `Commands.spawn_npc_clone/3`:

```elixir
@spec get_npc_blueprint(String.t()) ::
        {:ok, %{
           id: String.t(),
           name: String.t(),
           short_description: String.t(),
           long_description: String.t()
         }}
        | {:error, :no_such_blueprint}
def get_npc_blueprint(blueprint_id) when is_binary(blueprint_id) do
  case Repo.get(NPCBlueprint, blueprint_id) do
    nil -> {:error, :no_such_blueprint}
    %NPCBlueprint{} = bp -> {:ok, Map.take(bp, [:id, :name, :short_description, :long_description])}
  end
end
```

## New: `get_npc_clone/1`

Supports the post-dispatch re-query in `Commands.spawn_npc_clone/3` (so the wrapper can return the assigned serial):

```elixir
@spec get_npc_clone(String.t()) ::
        {:ok, %{
           id: String.t(),
           blueprint_id: String.t(),
           serial: integer(),
           name: String.t(),
           room_id: String.t()
         }}
        | {:error, :no_such_clone}
def get_npc_clone(clone_id) when is_binary(clone_id) do
  case Repo.get(NPCClone, clone_id) do
    nil -> {:error, :no_such_clone}
    %NPCClone{} = c ->
      {:ok,
       %{
         id: c.id,
         blueprint_id: c.blueprint_id,
         serial: c.serial,
         name: c.name,
         room_id: c.room_id
       }}
  end
end
```

## New: `find_clone_in_room_by_name/2`

Supports the pre-dispatch per-room name-collision check:

```elixir
@spec find_clone_in_room_by_name(String.t(), String.t()) ::
        {:ok, %{id: String.t(), name: String.t()}}
        | {:error, :no_such_clone}
def find_clone_in_room_by_name(room_id, name) when is_binary(room_id) and is_binary(name) do
  needle = normalize_name(name)

  rows =
    from(c in NPCClone,
      where: c.room_id == ^room_id,
      select: %{id: c.id, name: c.name}
    )
    |> Repo.all()

  case Enum.find(rows, fn r -> normalize_name(r.name) == needle end) do
    nil -> {:error, :no_such_clone}
    found -> {:ok, found}
  end
end
```

The case-insensitive comparison + `normalize_name/1` matches the existing semantic from feature 007 / 006.

## Unchanged: `look_room/1`

The function continues to populate `RoomView.npcs` by calling `list_npcs_in_room/1`. Return shape unchanged.

## Index utilization

| Query                                | Index used                                 |
|--------------------------------------|--------------------------------------------|
| `list_npcs_in_room/1`                | `npc_clones(room_id)`                       |
| `resolve_npc_in_room/2`              | `npc_clones(room_id)` then in-process filter |
| `get_npc_blueprint/1`                | PK on `npc_blueprints.id`                   |
| `get_npc_clone/1`                    | PK on `npc_clones.id`                       |
| `find_clone_in_room_by_name/2`       | `npc_clones(room_id)` then in-process filter |
| `WorldProjector.next_serial_for_blueprint/1` | `npc_clones(blueprint_id)`         |

## Caller impact

- `Examine.long_description_of_npc/1`: change `Schemas.NPC` → `Schemas.NPCClone`. Same query shape.
- `Commands.take/2` (feature 007 NPC fall-through): no change. Continues to call `resolve_npc_in_room/2`; the underlying table changed but the public contract did not.
- `ContextSnapshot.render/3`: no change. Continues to read `room.npcs` from `RoomView.npcs`.
- LiveView surfaces: no change. `RoomView.npcs` is still a list of `%{id, name, short_description}` maps.
