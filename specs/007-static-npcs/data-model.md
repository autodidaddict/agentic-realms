# Phase 1 Data Model: Static NPCs

## 1. Read-model schema: `world_npcs`

New table. One row per NPC currently in the persisted world.

| Column            | Type        | Constraints                                            | Notes                                              |
|-------------------|-------------|--------------------------------------------------------|----------------------------------------------------|
| `id`              | `binary_id` | PK, NOT NULL                                           | Stable UUID. Matches the `npc_id` in events.       |
| `name`            | `string`    | NOT NULL                                               | Display name (FR-001). Case preserved.             |
| `short_description` | `string`  | NOT NULL                                               | Used in the room view (FR-005).                    |
| `long_description`  | `text`    | NOT NULL                                               | Rendered on examination (FR-006). FR-001 forbids empty. |
| `room_id`         | `binary_id` | NOT NULL, FK → `world_rooms.id` (`on_delete: :restrict`) | NPCs always live in a room (FR-002).               |
| `inserted_at`     | `utc_datetime` | NOT NULL                                            | Standard timestamps.                               |
| `updated_at`      | `utc_datetime` | NOT NULL                                            |                                                    |

**Indexes**:
- `world_npcs(room_id)` — supports `list_npcs_in_room/1` and the room-view query.
- `world_npcs(room_id, LOWER(name))` — UNIQUE. Enforces FR-001a at the DB layer (per-room display name uniqueness, case-insensitive).

**Why no `fixed`/`takeable` column**: every NPC in this feature is un-gettable by virtue of being an NPC. Exposing a flag now would require deciding what `false` means (a "takeable" NPC? a "summonable" NPC?), and that decision is out of scope. The un-gettable contract is enforced at the take-command boundary (`Commands.take/2`), not at the schema. Future features that need per-NPC takeability can add the column then with no schema rewrite.

**Why no `player_id` column** (unlike `world_objects`): NPCs cannot exist in inventories (FR-002). The single-location invariant for NPCs is "exactly one room"; there is no "exactly one room OR exactly one player" disjunction. A simple `room_id NOT NULL` constraint expresses this.

**Ecto schema** (`lib/agenticrealms/world/schemas/npc.ex`):

```elixir
defmodule AgenticRealms.World.Schemas.NPC do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "world_npcs" do
    field :name, :string
    field :short_description, :string
    field :long_description, :string

    belongs_to :room, AgenticRealms.World.Schemas.Room, type: :binary_id

    timestamps(type: :utc_datetime)
  end
end
```

## 2. Aggregate state extension: `Room`

The `Room` aggregate struct grows two new fields:

```elixir
defstruct id: nil,
          name: nil,
          description: nil,
          exits: %{},
          object_ids: MapSet.new(),
          npc_ids: MapSet.new(),          # NEW
          npc_names_lower: MapSet.new()   # NEW
```

**Invariants enforced**:
- `npc_id` must not already be in `npc_ids` when `SpawnNPC` is dispatched → `{:error, :npc_already_in_room}`.
- `String.downcase(name)` must not already be in `npc_names_lower` → `{:error, :npc_name_taken_in_room}` (FR-001a).
- The room must exist (`id != nil`) → `{:error, :room_not_found}`.

**State transition** (only one in this feature):

```text
SpawnNPC{room_id, npc_id, name, short_description, long_description}
  ↓ (aggregate handler validates)
NPCSpawnedInRoom{room_id, npc_id, name, short_description, long_description}
  ↓ (apply/2)
%Room{
  npc_ids: MapSet.put(npc_ids, npc_id),
  npc_names_lower: MapSet.put(npc_names_lower, String.downcase(name))
}
```

There is no `NPCDespawned` event, no `NPCMoved` event, no `NPCRemovedFromRoom` event. The state transition graph for NPCs has exactly one transition (none → spawned). Per Q2 / FR-017b, world-reset operations rebuild the persisted world wholesale via the event store reset path — they do not raise per-NPC removal events.

## 3. Domain event: `NPCSpawnedInRoom`

```elixir
defmodule AgenticRealms.World.Events.NPCSpawnedInRoom do
  @derive Jason.Encoder
  @enforce_keys [
    :room_id,
    :npc_id,
    :name,
    :short_description,
    :long_description
  ]
  defstruct [
    :room_id,
    :npc_id,
    :name,
    :short_description,
    :long_description,
    version: 1
  ]
end
```

**Mirrors `ObjectPlacedInRoom`** — same shape, same encoding posture (`Jason.Encoder` derive for event-store serialization), same `version: 1` field for future schema evolution.

## 4. Command: `SpawnNPC`

```elixir
defmodule AgenticRealms.World.Commands.SpawnNPC do
  @enforce_keys [
    :room_id,
    :npc_id,
    :name,
    :short_description,
    :long_description
  ]
  defstruct [
    :room_id,
    :npc_id,
    :name,
    :short_description,
    :long_description
  ]
end
```

Routed to `Room` aggregate via the existing `World.Router`.

## 5. UI event: `RoomNPCArrived`

```elixir
# Inside lib/agenticrealms/world/ui_events.ex, alongside the existing
# RoomPlayerArrived / RoomPlayerLeft / RoomObjectTaken / RoomObjectDropped /
# PlayerCurrentRoomChanged / PlayerInventoryChanged modules:

defmodule AgenticRealms.World.UIEvents.RoomNPCArrived do
  @enforce_keys [:room_id, :npc_id, :npc_name]
  defstruct [:room_id, :npc_id, :npc_name]
end
```

Transient PubSub message — never persisted. Broadcast on the `room:<room_uuid>` topic in response to `NPCSpawnedInRoom`. Carries the NPC's display name so `GameLive` does not need to re-query.

## 6. `RoomView` struct extension

```elixir
defmodule AgenticRealms.World.RoomView do
  @enforce_keys [
    :id,
    :name,
    :description,
    :exits,
    :objects,
    :other_players,
    :npcs                # NEW
  ]
  defstruct [:id, :name, :description, :exits, :objects, :other_players, :npcs]
end
```

`npcs` is a list of maps shaped like `objects`: `%{id: String.t(), name: String.t(), short_description: String.t()}`. The `long_description` is intentionally omitted from the room view (FR-005); it is fetched on-demand by `Examine` only when needed.

## 7. `Examine.Match` extension

```elixir
defmodule AgenticRealms.World.Examine.Match do
  @enforce_keys [:target_kind, :name]
  defstruct [:target_kind, :name, :long_description]

  @type target_kind :: :object | :player | :npc       # :npc is new
  @type t :: %__MODULE__{
          target_kind: target_kind(),
          name: String.t(),
          long_description: String.t() | nil          # nil only for :player
        }
end
```

For NPCs, `long_description` is always populated (FR-001 enforces non-empty long descriptions; the schema's `NOT NULL` constraint enforces it at the DB layer).

## 8. `Examine` resolution decision tree (extended)

Inherits the three-stage tree from feature 006 (exact > partial; inventory > room; mixed-kind tie → refuse) with NPCs added to the **room-only** scope.

```text
gather_scope(player_id):
  → %{
      room_id,
      room_objects:   list of {id, name, short_description},
      inventory:      list of {id, name, short_description},
      players:        list of {id, username} including the acting player,
      npcs:           list of {id, name, short_description}   # NEW
    }

resolve(scope, needle):
  → Stage 1: exact, case-insensitive matches in room_objects + inventory + players + npcs
    - total == 0      → resolve_partial(scope, needle)
    - total == 1      → Match builder for the unique hit
    - any cross-kind tie (object + player, object + npc, player + npc, etc.) → {:error, :ambiguous_mixed_kind}
    - all hits same kind:
        - all objects (room + inventory): inventory wins; multi-inventory → :ambiguous_in_inventory; multi-room only → :ambiguous_in_room
        - all players: > 1 → :ambiguous_player
        - all npcs:    > 1 → :ambiguous_npc                    # NEW

  → Stage 2 (partial): substring match across all four scopes
    - 0 → :no_such_target
    - 1 → Match builder for the unique hit
    - >1 → :ambiguous_partial
```

**NPCs do NOT participate in inventory matching.** The `inventory > room` tiebreak only triggers when all remaining hits are objects. An NPC + same-named-object exact tie immediately refuses with `:ambiguous_mixed_kind`.

**Self-aliases** (`me`, `self`, `__self__`) continue to short-circuit to the acting player. NPCs cannot be self-examined.

## 9. "Also here" section contract

Rendered in `GameComponents`'s room-view component. Section appears only when `room.npcs` is non-empty.

**HEEx structure** (one canonical option — the actual class names follow the existing room-view CSS conventions):

```heex
<div :if={@room.npcs != []} class="room-section also-here">
  <span class="room-section-label">Also here:</span>
  <ul class="room-section-list">
    <li :for={npc <- @room.npcs} class="also-here-entry">
      <span class="also-here-name"><%= npc.name %></span>
      <span :if={npc.short_description not in [nil, ""]} class="also-here-short">
        — <%= npc.short_description %>
      </span>
    </li>
  </ul>
</div>
```

**Acceptance contract**:
- Section heading is the literal string `Also here:` (case preserved per FR-004).
- Each NPC is listed by display name; the short description is shown alongside (FR-005 makes this optional, but we include it for parity with the existing object listing's `— short description` format).
- When `room.npcs == []`, the entire section node is omitted (`:if={@room.npcs != []}`).
- Section ordering in the room view is: room description → exits → objects → other players → **also here** → input prompt. (Putting it after "other players" emphasizes "NPCs are non-player inhabitants of the room"; placing it before the input prompt keeps it discoverable in the player's reading flow.)

## 10. Detail entry contract for examined NPCs

The new render branch in `GameComponents.log_entry/1`:

```elixir
def log_entry(%{kind: :detail, target_kind: :npc} = assigns) do
  ~H"""
  <div class="log-entry detail detail-npc">
    <div class="detail-name"><%= @name %></div>
    <div class="detail-body"><%= @long_description %></div>
  </div>
  """
end
```

Same shape as the existing object branch (`detail detail-object`), differing only in the BEM modifier class (`detail-npc` vs `detail-object`) for any future styling work. The player branch (`detail detail-player`) remains unchanged — that one still renders the minimal `<display-name> is a player.` line.

## 11. Constraints / invariants summary

| ID  | Invariant                                                                                                                             | Enforced by                                                                                                              |
|-----|---------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| I-1 | Every NPC has exactly one room as its location (FR-002).                                                                              | `world_npcs.room_id NOT NULL` + FK to `world_rooms`.                                                                     |
| I-2 | Every NPC has a non-empty long description (FR-001).                                                                                  | `world_npcs.long_description NOT NULL` + `Room` aggregate handler validates non-empty on dispatch.                       |
| I-3 | Per-room display name uniqueness (FR-001a).                                                                                            | `Room.npc_names_lower` aggregate state + UNIQUE index on `(room_id, LOWER(name))`.                                       |
| I-4 | NPCs never appear in inventory.                                                                                                       | No `player_id` column on `world_npcs`; `Examine` scope excludes NPCs from inventory matching.                            |
| I-5 | NPCs are un-gettable.                                                                                                                 | `Commands.take/2` fallback to `Queries.resolve_npc_in_room/2`; positive match returns `{:error, :object_is_fixed}`.       |
| I-6 | Examining an NPC emits no witness entry to other players (FR-010).                                                                    | `Examine` is a pure read facade; no PubSub broadcast on success.                                                          |
| I-7 | NPC arrival entries fire only on `NPCSpawnedInRoom` events; no departure entry ever fires.                                            | Only one event type defined; broadcaster has only one new handler clause; no `NPCDespawned` event exists in this feature. |
| I-8 | Arrival entries are delivered to every concurrent session of every player in the destination room.                                    | Inherits from existing `Phoenix.PubSub.broadcast/3` fan-out on the `room:<room_uuid>` topic.                              |
