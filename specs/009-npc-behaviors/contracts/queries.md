# Contract: `Queries` Module Additions

Two new public functions support the behavior interpreter's lookups. No existing function signatures change.

## New: `get_room_behaviors/1`

```elixir
@spec get_room_behaviors(String.t()) ::
        {:ok, [map()]} | {:error, :no_such_room}
def get_room_behaviors(room_id) when is_binary(room_id) do
  case Repo.get(Room, room_id) do
    nil -> {:error, :no_such_room}
    %Room{behaviors: behaviors} -> {:ok, behaviors || []}
  end
end
```

Used by `Behaviors.Interpreter` to load room-level behaviors for the trigger room. The `|| []` defensive default handles any edge case where a row predates the column migration (shouldn't happen — the migration sets `NOT NULL DEFAULT '[]'::jsonb`, but the defensive default costs nothing).

## New: `list_npc_clones_in_room_with_behaviors/1`

```elixir
@spec list_npc_clones_in_room_with_behaviors(String.t()) ::
        [%{id: String.t(), name: String.t(), serial: integer(), behaviors: [map()]}]
def list_npc_clones_in_room_with_behaviors(room_id) when is_binary(room_id) do
  from(c in NPCClone,
    where: c.room_id == ^room_id,
    order_by: c.serial,
    select: %{id: c.id, name: c.name, serial: c.serial, behaviors: c.behaviors}
  )
  |> Repo.all()
end
```

Used by `Behaviors.Interpreter` to enumerate NPC clones in the trigger room and dispatch each one's behaviors.

**Ordering**: by `serial` ascending. The deterministic order satisfies FR-008a's "within NPCs, the firing order is deterministic." For a starter map with one clone per blueprint per room, the order question is academic, but it's locked in for future multi-clone content.

**Performance**: single indexed read against `npc_clones(room_id)`. The query selects only what the interpreter needs (clone id/name/serial/behaviors). Long descriptions and other heavy fields are NOT selected — keeps the firing path light.

## Unchanged: existing query functions

- `list_npcs_in_room/1` (used by room view + `Examine`) — unchanged. Returns id/name/short_description, no behaviors. Behaviors are not exposed to player-facing queries.
- `resolve_npc_in_room/2` — unchanged.
- `get_npc_blueprint/1` — unchanged. (Behaviors live on the row but aren't returned by this projection.)
- `get_npc_clone/1` — unchanged.

The interpreter is the only consumer that needs `behaviors`. No public-facing surface exposes them.

## Index utilization

| Query                                          | Index used                                |
|------------------------------------------------|-------------------------------------------|
| `get_room_behaviors/1`                         | PK on `world_rooms.id`                    |
| `list_npc_clones_in_room_with_behaviors/1`     | `npc_clones(room_id)` + sort on `serial`  |

## Module aliases

The `Schemas.Room` alias is already present in `Queries`. No new aliases needed.

## Test surface

Covered by `interpreter_test.exs` (functional verification via the interpreter's behavior) plus a focused unit test in `queries_test.exs` if one exists. Per the project convention from features 007/008, queries unit-test coverage often piggybacks on the integration test rather than living in a dedicated file.
