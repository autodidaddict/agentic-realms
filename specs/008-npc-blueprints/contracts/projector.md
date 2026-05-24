# Contract: `WorldProjector` Handler Changes

Three handler clauses in `lib/agenticrealms/world/projections/world_projector.ex` change or are added.

## New handler: `NPCBlueprintCreated`

```elixir
def handle(
      %NPCBlueprintCreated{
        blueprint_id: bp_id,
        name: name,
        short_description: short,
        long_description: long
      },
      _meta
    ) do
  Repo.insert!(
    %NPCBlueprint{
      id: bp_id,
      name: name,
      short_description: short,
      long_description: long,
      is_synthetic: false
    },
    on_conflict: :nothing,
    conflict_target: :id
  )

  :ok
end
```

- Idempotent by `id`. Authored blueprints have `is_synthetic: false`.
- No relationship to existing tables. Pure insert.

## New handler: `NPCClonedFromBlueprint`

```elixir
def handle(
      %NPCClonedFromBlueprint{
        blueprint_id: bp_id,
        clone_id: cid,
        room_id: rid,
        serial: serial,
        name: name,
        short_description: short,
        long_description: long
      },
      _meta
    ) do
  Repo.insert!(
    %NPCClone{
      id: cid,
      blueprint_id: bp_id,
      serial: serial,
      name: name,
      short_description: short,
      long_description: long,
      room_id: rid
    },
    on_conflict: :nothing,
    conflict_target: :id
  )

  :ok
end
```

- Idempotent by `id`. Inserts use only the event payload — never reads the blueprint table to materialize clone data (the event already contains the full-copy snapshot per I-3).
- The `(blueprint_id, serial)` and `(room_id, LOWER(name))` unique indexes are NOT specified as `conflict_target` because PK conflict is the only expected replay collision. A unique-index violation during a forward execution (not replay) indicates a real conflict and SHOULD raise — it's a sign of a pre-dispatch check that was bypassed (e.g., concurrent spawns racing past the read-model check). The projector raises in that case and the event-store position does NOT advance, providing a debug breadcrumb.

## Rewritten handler: `NPCSpawnedInRoom` (legacy)

Replaces feature 007's handler that inserted into `world_npcs`. New body:

```elixir
def handle(
      %NPCSpawnedInRoom{
        room_id: rid,
        npc_id: nid,
        name: name,
        short_description: short,
        long_description: long
      },
      _meta
    ) do
  bp_id = SyntheticBlueprintId.derive(name, short, long)

  Repo.insert!(
    %NPCBlueprint{
      id: bp_id,
      name: name,
      short_description: short,
      long_description: long,
      is_synthetic: true
    },
    on_conflict: :nothing,
    conflict_target: :id
  )

  serial = next_serial_for_blueprint(bp_id)

  Repo.insert!(
    %NPCClone{
      id: nid,
      blueprint_id: bp_id,
      serial: serial,
      name: name,
      short_description: short,
      long_description: long,
      room_id: rid
    },
    on_conflict: :nothing,
    conflict_target: :id
  )

  :ok
end

defp next_serial_for_blueprint(bp_id) do
  from(c in NPCClone, where: c.blueprint_id == ^bp_id, select: max(c.serial))
  |> Repo.one()
  |> case do
    nil -> 1
    n -> n + 1
  end
end
```

### Idempotency guarantees

- Replay 1: synthetic blueprint inserted. Clone `nid` inserted with serial `1`.
- Replay 2: synthetic blueprint `on_conflict: :nothing` no-ops. Clone `nid` `on_conflict: :nothing` no-ops (PK already exists). Net change: nothing.
- Replay with TWO legacy events for the same (name, short, long) but different `npc_id`: first event inserts blueprint + clone with serial 1. Second event no-ops blueprint, inserts clone 2 with serial 2 (because the MAX query sees the first clone).
- Replay TWICE with the above: replay 1 = same as above. Replay 2 = both clones no-op on PK conflict. Net change: nothing.

## New module: `World.Projections.SyntheticBlueprintId`

```elixir
defmodule AgenticRealms.World.Projections.SyntheticBlueprintId do
  @moduledoc """
  Deterministic synthetic blueprint id derivation for feature 008's legacy
  event replay path (FR-019 / FR-020 / FR-021).

  Same `(name, short_description, long_description)` tuple always produces
  the same id. Different tuples produce different ids.
  """

  @namespace UUID.uuid5(:nil, "agenticrealms:legacy-npc-spawn")

  @spec derive(String.t(), String.t(), String.t()) :: String.t()
  def derive(name, short, long)
      when is_binary(name) and is_binary(short) and is_binary(long) do
    UUID.uuid5(@namespace, "#{name}|#{short}|#{long}")
  end
end
```

The namespace UUID is a constant — same on every developer's machine, every CI run, every production replay. The per-event UUID5 is fully deterministic given the payload.

## Handler-list growth in `WorldProjector`

Before (feature 007):
- `RoomCreated`
- `ExitAdded`
- `ObjectPlacedInRoom`
- `ObjectTakenFromRoom`
- `ObjectDroppedInRoom`
- `NPCSpawnedInRoom` (inserts into `world_npcs`)

After (feature 008):
- `RoomCreated` *(unchanged)*
- `ExitAdded` *(unchanged)*
- `ObjectPlacedInRoom` *(unchanged)*
- `ObjectTakenFromRoom` *(unchanged)*
- `ObjectDroppedInRoom` *(unchanged)*
- `NPCSpawnedInRoom` *(REWRITTEN — synthetic blueprint + clone insert)*
- `NPCBlueprintCreated` *(NEW)*
- `NPCClonedFromBlueprint` *(NEW)*

## Subscription reset (FR-021a)

The Ecto migration responsible for this feature includes a final step:

```elixir
def change do
  drop_if_exists table(:world_npcs)

  create table(:npc_blueprints, primary_key: false) do
    # ... see data-model.md §1 ...
  end

  create table(:npc_clones, primary_key: false) do
    # ... see data-model.md §2 ...
  end

  # FR-021a: reset the WorldProjector subscription so it replays the entire
  # event store on next application startup, exercising the new schema +
  # the synthetic-blueprint legacy projection path.
  execute("""
  DELETE FROM subscriptions
  WHERE subscription_name = 'AgenticRealms.World.Projections.WorldProjector'
  """, "")
end
```

The reverse direction (down migration) is intentionally a no-op for the subscription reset — rolling back the migration drops the new tables and recreates `world_npcs`, but the subscription state's "correct" pre-migration position is not generally recoverable. In practice, rolling back this migration in a deployed environment means rebuilding the world from event store anyway, which is a wholesale operation.
