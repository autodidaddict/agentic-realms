# Contract: `World.Behaviors.Interpreter`

Commanded event handler. Subscribes to the two domain events that drive behavior triggers (`PlayerSpawned`, `PlayerMoved`) and dispatches matching behaviors. Produces transient PubSub broadcasts only — NEVER emits domain events.

## Module shape

```elixir
defmodule AgenticRealms.World.Behaviors.Interpreter do
  @moduledoc """
  Commanded event handler that processes player-movement events and fires
  any behaviors attached to the rooms and NPC clones involved.

  Configured with `start_from: :current` so historical events are NEVER
  replayed through this handler — see `specs/009-npc-behaviors/research.md`
  R1 for the replay-safety rationale.

  Configured with `consistency: :strong` so that `Commands.move/2` and
  `Commands.spawn/2` block until behaviors have fired and broadcast.
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    start_from: :current,
    consistency: :strong

  alias AgenticRealms.World.Events.{PlayerSpawned, PlayerMoved}
  alias AgenticRealms.World.Behaviors.ActionExecutor
  alias AgenticRealms.World.Queries

  # handle/2 clauses below.
end
```

## Handler clauses

### `PlayerSpawned`

```elixir
def handle(%PlayerSpawned{player_id: pid, room_id: room_id}, _meta) do
  fire_room_then_npcs(room_id, "player_entered", pid)
  :ok
end
```

A player has spawned into `room_id` for the first time. Only `player_entered` fires (there's no source room — no `player_left`).

### `PlayerMoved`

```elixir
def handle(
      %PlayerMoved{player_id: pid, from_room_id: from, to_room_id: to},
      _meta
    ) do
  fire_room_then_npcs(from, "player_left", pid)
  fire_room_then_npcs(to, "player_entered", pid)
  :ok
end
```

A player moved. First fire `player_left` behaviors in the source room, then `player_entered` behaviors in the destination room. The two firings are sequential to preserve a clean temporal narrative for the player (goodbye, then hello).

## Core dispatch logic

```elixir
defp fire_room_then_npcs(room_id, trigger_string, triggering_player_id) do
  # Step 1: room's own behaviors (FR-008a — room first).
  case Queries.get_room_behaviors(room_id) do
    {:ok, behaviors} ->
      fire_entity_behaviors(
        {:room, room_id},
        behaviors,
        trigger_string,
        room_id,
        triggering_player_id
      )

    {:error, _} ->
      :ok
  end

  # Step 2: NPC clones in the room, ordered by serial.
  clones = Queries.list_npc_clones_in_room_with_behaviors(room_id)

  Enum.each(clones, fn clone ->
    fire_entity_behaviors(
      {:npc_clone, clone},
      clone.behaviors,
      trigger_string,
      room_id,
      triggering_player_id
    )
  end)
end

defp fire_entity_behaviors(_speaker_ctx, [] = _no_behaviors, _trigger, _room_id, _pid),
  do: :ok

defp fire_entity_behaviors(speaker_ctx, behaviors, trigger_string, room_id, triggering_player_id) do
  matching =
    Enum.filter(behaviors, fn b -> Map.get(b, "trigger") == trigger_string end)

  Enum.each(matching, fn behavior ->
    actions = Map.get(behavior, "actions", [])

    Enum.each(actions, fn action ->
      ActionExecutor.execute(speaker_ctx, action, room_id, triggering_player_id)
    end)
  end)
end
```

`speaker_ctx` is either `{:room, room_id}` (for room behaviors) or `{:npc_clone, %{id, name, serial, ...}}` (for NPC behaviors). The `ActionExecutor` uses this to determine the speaker name for `:npc_speech` (the clone's display name) or to set `:room_speech` (no speaker).

## Trust posture

The interpreter does NOT call `Validator.validate/1` at firing time. It assumes the stored data was validated at write time. If a malformed action arrives (unlikely given the validator runs at seed time), the `ActionExecutor` pattern-matches and logs+skips it rather than crashing.

## Replay safety

`start_from: :current` ensures the interpreter never sees historical events. On boot, Commanded subscribes the handler from the current event-store HEAD position. Replaying the store for any reason (`mix event_store.reset`, projector rebuild, etc.) does NOT re-fire historical PlayerSpawned/PlayerMoved through this handler.

## Output semantics

The interpreter produces transient PubSub broadcasts via `ActionExecutor`. It does not:
- Emit any domain events (no `Commands.dispatch` calls).
- Write to any database table.
- Maintain any handler-side state (no aggregate, no projection table).

If the interpreter crashes mid-event, Commanded's at-least-once delivery would retry. Since the only side effects are PubSub broadcasts, retried firings would produce duplicate log entries on player sessions. This is acceptable for this feature's scope — a future feature can add idempotency via a "fired" tracking column on something if it ever matters; for the seed + small movements case, it doesn't.

## Test surface

`test/agenticrealms/world/behaviors/interpreter_test.exs`:

- Setup: insert rooms + blueprints + clones via direct `Repo.insert!` (bypassing Commanded for fixture speed).
- For each scenario: synthesize a `PlayerSpawned` or `PlayerMoved` struct, call `Interpreter.handle/2` directly, subscribe to relevant player topics, assert the expected `BehaviorUtterance` messages arrive.

Cases covered:
1. Empty room behaviors + empty NPC behaviors → no broadcasts.
2. Room-only behavior on `player_entered` → single `:room_speech` to triggering player.
3. NPC-only behavior on `player_entered` → `:npc_speech` to triggering player + other players in room.
4. Room + NPC behaviors → room speech BEFORE NPC speech (FR-008a verification).
5. Multi-behavior list on same trigger → all fire in authored order.
6. Multi-action behavior → all actions fire in authored order.
7. `player_left` in source room → behaviors fire (the leaving player explicitly receives `:npc_speech`).
8. Non-matching trigger → no firing (e.g., a `player_left` event when only `player_entered` behaviors exist).
9. Multiple NPC clones with different serials → fire in serial order.
