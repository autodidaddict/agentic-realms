# Contract: `Examine` Module Extension

Extends `lib/agenticrealms/world/examine.ex` to include NPCs as a third examinable target type. The three-stage resolution decision tree from feature 006 is preserved; NPCs join the room scope only.

## `Examine.Match` type extension

See `data-model.md` §7. `target_kind` becomes `:object | :player | :npc`. The struct shape is unchanged; only the type union widens.

## `gather_scope/1` extension

Before (feature 006):

```elixir
defp gather_scope(player_id) do
  with {:ok, room_id} <- Queries.current_room_of(player_id),
       {:ok, room_view} <- Queries.look_room(player_id) do
    inventory = Queries.list_inventory(player_id)

    players =
      case acting_username(player_id) do
        {:ok, name} -> [%{id: player_id, username: name} | room_view.other_players]
        :error -> room_view.other_players
      end

    {:ok,
     %{
       room_id: room_id,
       room_objects: room_view.objects,
       inventory: inventory,
       players: players
     }}
  else
    ...
  end
end
```

After:

```elixir
defp gather_scope(player_id) do
  with {:ok, room_id} <- Queries.current_room_of(player_id),
       {:ok, room_view} <- Queries.look_room(player_id) do
    inventory = Queries.list_inventory(player_id)

    players =
      case acting_username(player_id) do
        {:ok, name} -> [%{id: player_id, username: name} | room_view.other_players]
        :error -> room_view.other_players
      end

    {:ok,
     %{
       room_id: room_id,
       room_objects: room_view.objects,
       inventory: inventory,
       players: players,
       npcs: room_view.npcs            # NEW — directly from RoomView.npcs
     }}
  else
    ...
  end
end
```

The `RoomView.npcs` field is the same shape as `RoomView.objects` (`%{id, name, short_description}`), so the new scope key drops in with no additional Repo round-trip.

## `resolve/2` extension (Stage 1: exact matching)

Updated decision tree:

```elixir
defp resolve(scope, target) do
  exact_room = filter_objects_exact(scope.room_objects, target)
  exact_inv  = filter_objects_exact(scope.inventory, target)
  exact_pl   = filter_players_exact(scope.players, target)
  exact_npc  = filter_npcs_exact(scope.npcs, target)        # NEW

  total =
    length(exact_room) + length(exact_inv) +
    length(exact_pl) + length(exact_npc)

  cond do
    total == 0 ->
      resolve_partial(scope, target)

    total == 1 ->
      from_first_match(exact_room, exact_inv, exact_pl, exact_npc)

    cross_kind_tie?(exact_room, exact_inv, exact_pl, exact_npc) ->
      {:error, :ambiguous_mixed_kind}

    length(exact_pl) > 1 ->
      {:error, :ambiguous_player}

    length(exact_npc) > 1 ->
      {:error, :ambiguous_npc}      # NEW — should be unreachable
                                    # given FR-001a per-room uniqueness
                                    # is enforced; defensive coverage.

    true ->
      # Remaining: all objects (room + inventory).
      resolve_object_tiebreak(exact_room, exact_inv)
  end
end

defp cross_kind_tie?(room, inv, pl, npc) do
  # Two-or-more *kinds* simultaneously matched at exact level.
  # Objects (room + inv) count as one kind; players one kind; npcs one kind.
  has_obj = room != [] or inv != []
  has_pl  = pl != []
  has_npc = npc != []
  Enum.count([has_obj, has_pl, has_npc], & &1) > 1
end

defp from_first_match([obj], [], [], []), do: {:ok, object_match(obj)}
defp from_first_match([], [obj], [], []), do: {:ok, object_match(obj)}
defp from_first_match([], [], [pl], []),  do: {:ok, player_match(pl)}
defp from_first_match([], [], [], [npc]), do: {:ok, npc_match(npc)}   # NEW
```

The earlier `from_first_match/4` arity-4 helper (it was `from_first_match(_module, ...)` in 006 — module argument unused) is simplified by dropping the unused module argument.

## `resolve_partial/2` extension (Stage 2: substring matching)

```elixir
defp resolve_partial(scope, target) do
  partial_room = filter_objects_partial(scope.room_objects, target)
  partial_inv  = filter_objects_partial(scope.inventory, target)
  partial_pl   = filter_players_partial(scope.players, target)
  partial_npc  = filter_npcs_partial(scope.npcs, target)        # NEW

  total =
    length(partial_room) + length(partial_inv) +
    length(partial_pl) + length(partial_npc)

  case total do
    0 -> {:error, :no_such_target}
    1 -> from_first_match(partial_room, partial_inv, partial_pl, partial_npc)
    _ -> {:error, :ambiguous_partial}
  end
end
```

## New filter helpers

```elixir
defp filter_npcs_exact(npcs, target),
  do: Enum.filter(npcs, fn n -> String.downcase(n.name) == target end)

defp filter_npcs_partial(npcs, target),
  do: Enum.filter(npcs, fn n -> String.contains?(String.downcase(n.name), target) end)
```

## New match builder

```elixir
defp npc_match(%{name: name} = npc) do
  %Match{
    target_kind: :npc,
    name: name,
    long_description: long_description_of_npc(npc)
  }
end

defp long_description_of_npc(%{id: id}) do
  case AgenticRealms.Repo.get(AgenticRealms.World.Schemas.NPC, id) do
    %AgenticRealms.World.Schemas.NPC{long_description: ld} -> ld
    _ -> nil
  end
end
```

`long_description_of_npc/1` mirrors `long_description_of/1` for objects — the room-view projection omits the long description (FR-005), so the Examine module fetches it on-demand from the persisted entity. Per I-2, the NOT NULL constraint guarantees a non-nil result for any persisted NPC; the `_ -> nil` clause is a defensive guard against race conditions (NPC removed mid-examine — not possible in this feature, but cheap to handle).

## Error atom additions

The `@type error_reason` union grows to include `:ambiguous_npc`:

```elixir
@type error_reason ::
        :no_current_room
        | :no_such_target
        | :ambiguous_in_room
        | :ambiguous_in_inventory
        | :ambiguous_mixed_kind
        | :ambiguous_player
        | :ambiguous_npc           # NEW
        | :ambiguous_partial
```

`:ambiguous_npc` should be unreachable in practice (FR-001a guarantees per-room name uniqueness); defensive coverage in case a future bug bypasses the uniqueness layers.

## Self-examination unchanged

The `@self_aliases ~w(__self__ me self)` whitelist remains object/player-only. An NPC named "me" or "self" would NOT match self-aliases — the self-alias short-circuit runs before scope gathering, and a player typing `look me` always resolves to themselves.

Per the spec's edge-case section: NPCs do not participate in self-examination grammar. The current implementation already enforces this by structure.

## Telemetry

The existing `emit_telemetry/2` call site receives the new `:npc` target_kind for successful matches and `:ambiguous_npc` for the new error path. No telemetry schema change is required — `target_kind` is already free-form.
