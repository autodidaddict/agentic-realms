# Contract: `Commands.take/2` NPC Refusal Path

Extends `lib/agenticrealms/world/commands.ex`'s `take/2` so that `take <npc-name>` refuses through the existing fixed-object refusal pipeline. No new error atom is introduced; no new LiveView clause is required.

## Before (feature 003)

```elixir
def take(player_id, name) when is_integer(player_id) and is_binary(name) do
  with {:ok, room_id} <- Queries.current_room_of(player_id),
       {:ok, object_id} <- Queries.resolve_object_in_room(room_id, name),
       {:ok, false} <- check_not_fixed(object_id),
       object_name <- name_of(object_id),
       :ok <-
         WorldApp.dispatch(
           %TakeObject{room_id: room_id, player_id: player_id, object_id: object_id},
           consistency: :strong
         ) do
    {:ok, %{object_id: object_id, object_name: object_name}}
  else
    {:ok, true} -> {:error, :object_is_fixed}
    {:error, _} = err -> err
  end
end
```

## After (this feature)

```elixir
def take(player_id, name) when is_integer(player_id) and is_binary(name) do
  with {:ok, room_id} <- Queries.current_room_of(player_id) do
    case Queries.resolve_object_in_room(room_id, name) do
      {:ok, object_id} ->
        do_take(room_id, player_id, object_id)

      {:error, :no_such_object} ->
        # NPC fall-through: if no object matches but an NPC does, refuse
        # via the existing fixed-object path (FR-015).
        case Queries.resolve_npc_in_room(room_id, name) do
          {:ok, _npc_id} -> {:error, :object_is_fixed}
          {:error, :no_such_npc} -> {:error, :no_such_object}
          {:error, :ambiguous} -> {:error, :ambiguous}
        end

      other ->
        other
    end
  end
end

defp do_take(room_id, player_id, object_id) do
  with {:ok, false} <- check_not_fixed(object_id),
       object_name <- name_of(object_id),
       :ok <-
         WorldApp.dispatch(
           %TakeObject{room_id: room_id, player_id: player_id, object_id: object_id},
           consistency: :strong
         ) do
    {:ok, %{object_id: object_id, object_name: object_name}}
  else
    {:ok, true} -> {:error, :object_is_fixed}
    {:error, _} = err -> err
  end
end
```

## Behavior matrix

| Scope contents                                  | Input              | Result                                  |
|-------------------------------------------------|--------------------|------------------------------------------|
| `brass lantern` object in room (takeable)       | `take lantern`     | `{:ok, %{object_id, object_name}}`       |
| `reading lectern` object in room (fixed)        | `take lectern`     | `{:error, :object_is_fixed}`             |
| `Garrick the Innkeeper` NPC in room             | `take garrick`     | `{:error, :object_is_fixed}` ← **NEW**   |
| Empty room                                       | `take anything`    | `{:error, :no_such_object}`              |
| Two objects with same name in room (auth. bug)  | `take lantern`     | `{:error, :ambiguous}`                   |

## LiveView impact

**None on the existing branch logic**. The existing `{:error, :object_is_fixed}` clause in `game_live.ex:458-460` continues to render `"You can't take that."` — exactly the right copy for both fixed objects and NPCs.

```elixir
{:error, :object_is_fixed} ->
  {:noreply,
   socket |> echo(raw) |> append_log(%{kind: :system, text: "You can't take that."})}
```

## Why not surface NPC vs fixed-object distinction in the refusal?

FR-015 explicitly demands the same code path and same refusal shape. The LiveView already renders a generic "You can't take that." which is appropriate for both. Surfacing the distinction (e.g., "You can't take a person.") would:
- Require a new error atom or a new LiveView clause.
- Force a copy decision specific to NPCs.
- Diverge from the user's stated requirement (same flag type, same refusal).

If a future feature wants person-specific refusal text, it can branch then. This feature deliberately keeps the refusal uniform.

## LLM resolver impact

**None to the `take` tool**. The model still emits `{:take, name}` for any "pick up / grab / take X" phrasing (including "pick up the innkeeper" or "grab the old man"). The server-side resolution in `Commands.take/2` is what catches the NPC and refuses. This keeps the model's responsibility narrow: "classify the verb, extract the noun phrase" — not "decide whether the target is legal."

The IntentResolver's `look` tool description is the only resolver-side change (see `contracts/tools.md`).

## Tests added to `commands_take_test.exs`

1. **Happy path unchanged**: existing tests pass.
2. **NPC name maps to refusal**: seed a room with an NPC; call `Commands.take(player_id, "garrick")`; expect `{:error, :object_is_fixed}`.
3. **NPC + object with same name**: seed a room with an object named "garrick" AND an NPC named "garrick". Per FR-008 / R3, the object resolves first (it's the `resolve_object_in_room/2` happy path), so `take` returns the object. The NPC fall-through only fires when the object resolver returns `:no_such_object`. (This is the correct behavior — the player explicitly named a takeable thing; the NPC's matching name is incidental.)
4. **NPC in another room is not findable**: seed two rooms each with their own NPC; place the player in room A; call `take <NPC name from room B>`; expect `{:error, :no_such_object}`.
