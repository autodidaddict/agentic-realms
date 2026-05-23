# Contract: `Queries` Module Extensions

Two new public functions and one extended existing function in `lib/agenticrealms/world/queries.ex`.

## New: `list_npcs_in_room/1`

```elixir
@spec list_npcs_in_room(String.t()) ::
        [%{id: String.t(), name: String.t(), short_description: String.t()}]
def list_npcs_in_room(room_id) when is_binary(room_id) do
  from(n in NPC,
    where: n.room_id == ^room_id,
    order_by: n.name,
    select: %{id: n.id, name: n.name, short_description: n.short_description}
  )
  |> Repo.all()
end
```

**Contract**:
- Input: a room UUID.
- Output: a list of NPC summaries (one entry per NPC currently in the room), ordered alphabetically by display name.
- Excludes `long_description` from the projection — the room view does not need it (FR-005).
- Returns `[]` when no NPCs are present (consistent with `list_objects_in_room/1`).

The `NPC` alias is added to the existing `alias AgenticRealms.World.Schemas.{Room, Exit, Object, PlayerState}` line.

## New: `resolve_npc_in_room/2`

```elixir
@spec resolve_npc_in_room(String.t(), String.t()) ::
        {:ok, String.t()} | {:error, :no_such_npc | :ambiguous}
def resolve_npc_in_room(room_id, name) when is_binary(room_id) and is_binary(name) do
  needle = normalize_name(name)

  rows =
    from(n in NPC,
      where: n.room_id == ^room_id,
      select: %{id: n.id, name: n.name}
    )
    |> Repo.all()

  case Enum.filter(rows, fn r -> normalize_name(r.name) == needle end) do
    [] -> {:error, :no_such_npc}
    [%{id: id}] -> {:ok, id}
    _multiple -> {:error, :ambiguous}
  end
end
```

**Contract**:
- Mirrors `resolve_object_in_room/2` exactly. Same normalization helper (`normalize_name/1`), same case-insensitive comparison, same error atoms — except the "not found" atom is `:no_such_npc` (not `:no_such_object`) so callers can distinguish.
- Per FR-001a the `:ambiguous` case should never fire (per-room uniqueness is enforced at three layers); the clause exists as a safety net and matches the convention from `resolve_object_in_room/2`.

**Used by**: `World.Commands.take/2` (see `contracts/take_refusal.md`).

## Extended: `look_room/1`

The existing function gains one new field on the returned `RoomView`:

```elixir
def look_room(player_id) when is_integer(player_id) do
  with {:ok, room_id} <- current_room_of(player_id),
       %Room{} = room <- Repo.get(Room, room_id) do
    {:ok,
     %RoomView{
       id: room.id,
       name: room.name,
       description: room.description,
       exits: list_exits(room_id),
       objects: list_objects_in_room(room_id),
       other_players: list_other_players(room_id, player_id),
       npcs: list_npcs_in_room(room_id)     # NEW
     }}
  else
    {:error, :no_current_room} = err -> err
    nil -> {:error, :room_missing}
  end
end
```

The `RoomView` struct is updated (see `data-model.md` §6) so the new field is `@enforce_keys`-required, preventing any caller from accidentally omitting it.

## Index utilization

| Query                                   | Index used                                                              |
|-----------------------------------------|-------------------------------------------------------------------------|
| `list_npcs_in_room/1`                   | `world_npcs(room_id)`                                                   |
| `resolve_npc_in_room/2`                 | `world_npcs(room_id)` (then in-process name normalize+filter)           |

## No new module aliases

The `World.Schemas.NPC` alias is added once at the top of `queries.ex`. No other module structure changes.
