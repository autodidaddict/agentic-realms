# Contract: PlayerDiscoveredRoom event, projection, emission

## Event

```elixir
defmodule AgenticRealms.World.Events.PlayerDiscoveredRoom do
  @derive Jason.Encoder
  @enforce_keys [:player_id, :room_id, :discovered_at]
  defstruct [:player_id, :room_id, :discovered_at, version: 1]
end
```

## Schema

```elixir
defmodule AgenticRealms.World.Schemas.PlayerDiscoveredRoom do
  use Ecto.Schema

  @primary_key false
  schema "player_discovered_rooms" do
    field :player_id, :id, primary_key: true
    field :room_id, :binary_id, primary_key: true
    field :discovered_at, :utc_datetime, source: :discovered_at
  end
end
```

## Projection

`AgenticRealms.World.Projections.WorldProjector` gains a clause:

```elixir
def handle(
      %PlayerDiscoveredRoom{
        player_id: pid,
        room_id: rid,
        discovered_at: ts
      },
      _meta
    ) do
  Repo.insert!(
    %PlayerDiscoveredRoom{player_id: pid, room_id: rid, discovered_at: ts},
    on_conflict: :nothing,
    conflict_target: [:player_id, :room_id]
  )
  :ok
end
```

The composite-PK `on_conflict: :nothing` is the idempotency guarantee — replays and crash-recovery duplicates do not double-insert.

## Emission — invariant

**A row in `player_discovered_rooms` MUST originate from a `PlayerDiscoveredRoom` domain event handled by the projector. No code path in this project — not in `PlayerStateProjector`, not in any seed script, not in any test helper used outside the test environment, not in any future ad-hoc admin tool — may insert into this table directly. This is an unconditional invariant.**

The motivating rule is project-wide: every persistent fact in this codebase MUST flow through the command → aggregate → event → projector pipeline. There is no documented "simpler fallback" — direct DB writes that bypass event sourcing are forbidden even when the inserted row looks trivially idempotent.

## Emission — implementation

The existing `AgenticRealms.World.Player` aggregate (introduced in feature 003 to own `current_room_id`) gains a new field for discovered room ids and one new command. No new aggregate is introduced.

### New command

```elixir
defmodule AgenticRealms.World.Commands.RecordRoomDiscovery do
  @enforce_keys [:player_id, :room_id]
  defstruct [:player_id, :room_id]
end
```

### Aggregate extension (`lib/agenticrealms/world/player.ex`)

Add a `discovered_room_ids` field to the defstruct, plus an `execute/2` clause and an `apply/2` clause:

```elixir
defstruct id: nil,
          current_room_id: nil,
          # NEW for feature 012
          discovered_room_ids: MapSet.new()

# --- RecordRoomDiscovery ------------------------------------------------

def execute(%__MODULE__{discovered_room_ids: discovered}, %RecordRoomDiscovery{
      player_id: pid,
      room_id: rid
    }) do
  if MapSet.member?(discovered, rid) do
    # Already discovered — no event emitted. The aggregate's MapSet is
    # authoritative for idempotency; the projector NEVER pre-checks.
    :ok
  else
    %PlayerDiscoveredRoom{
      player_id: pid,
      room_id: rid,
      discovered_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end
end

# --- apply/2 (new clause) -----------------------------------------------

def apply(%__MODULE__{discovered_room_ids: discovered} = state, %PlayerDiscoveredRoom{
      room_id: rid
    }) do
  %__MODULE__{state | discovered_room_ids: MapSet.put(discovered, rid)}
end
```

**Identification**: aggregate id is `player_id`, already wired by feature 003's router config. `RecordRoomDiscovery` is added to the existing `dispatch [...]` list for `World.Player`.

**Why extend the existing aggregate**: the `World.Player` aggregate already owns the player's current location. Discovery is a tightly-related player fact (per-player, write-once-per-room, queried alongside `current_room_id` on every map render). Adding the `MapSet` to the existing struct is cheaper than introducing a parallel aggregate, keeps player facts in one place, and grows naturally toward future player-level event-sourced facts (quest progress, reputation, etc.).

**Dispatch wrapper** in `AgenticRealms.World.Commands`:

```elixir
@spec record_room_discovery(player_id :: pos_integer(), room_id :: binary_id()) :: :ok
def record_room_discovery(player_id, room_id) do
  WorldApp.dispatch(
    %RecordRoomDiscovery{player_id: player_id, room_id: room_id},
    consistency: :strong
  )
end
```

`consistency: :strong` matches the existing `PlayerStateProjector` convention so the read-model row is in place before the dispatcher returns.

## Call sites

`AgenticRealms.World.Projections.PlayerStateProjector` (the only call site in v1):

```elixir
def handle(%PlayerSpawned{player_id: pid, room_id: room_id}, _meta) do
  # ... existing current_room_id upsert ...
  :ok = AgenticRealms.World.Commands.record_room_discovery(pid, room_id)
  :ok
end

def handle(%PlayerMoved{player_id: pid, to_room_id: to}, _meta) do
  # ... existing current_room_id update (incl. FR-022 nullification) ...
  if room_exists?(to) do
    :ok = AgenticRealms.World.Commands.record_room_discovery(pid, to)
  end
  :ok
end
```

The projector unconditionally dispatches `RecordRoomDiscovery` on every spawn/move. The aggregate's `execute/2` short-circuits if the room is already discovered (no event emitted, no projection write). The projector does NOT pre-check the read model — that check is the aggregate's responsibility, in the right place (the event-sourced model).

**Dispatching a command from a projector handler** is an accepted pattern in Commanded (used elsewhere in the project for `spawn_npc_clone`'s synthetic-blueprint backfill). The projector is essentially acting as a small process-manager / saga that reacts to a triggering event by emitting a follow-up command.

## Test plan

- **Projection idempotency**: emit `PlayerDiscoveredRoom` twice with the same `(player_id, room_id)`; assert exactly one row.
- **Emission on spawn**: dispatch `SpawnPlayer` for a new player; assert the spawn room appears in `player_discovered_rooms` for that player.
- **Emission on move**: dispatch `MovePlayer` between two rooms; assert the destination is added to `player_discovered_rooms` if and only if it wasn't already there.
- **No double-emission on re-entry**: move to room A, move to room B, move back to room A; assert exactly one row for `(player_id, A)`.
- **Per-player isolation**: two players in the same room have independent discovery rows.
