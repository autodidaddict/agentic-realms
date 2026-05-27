# Contract: `world_objects` quest fields + viewer filter

## Schema extension

Extends the existing `AgenticRealms.World.Object` Ecto schema (`lib/agenticrealms/world/schemas/object.ex`).

```elixir
field :quest_player_id, :integer
field :quest_instance_id, :binary_id

belongs_to :quest_player, AgenticRealms.Accounts.Player,
  foreign_key: :quest_player_id, references: :id, define_field: false

belongs_to :quest_instance, AgenticRealms.World.QuestInstance,
  foreign_key: :quest_instance_id, references: :id, define_field: false
```

Backed by migration `<ts2>_extend_world_objects_with_quest_fields.exs`:

```sql
ALTER TABLE world_objects
  ADD COLUMN quest_player_id bigint REFERENCES players(id) ON DELETE SET NULL,
  ADD COLUMN quest_instance_id uuid REFERENCES quest_instances(id) ON DELETE CASCADE,
  ADD CONSTRAINT world_objects_quest_fields_paired
    CHECK ((quest_player_id IS NULL) = (quest_instance_id IS NULL));

CREATE INDEX world_objects_quest_instance_id_idx
  ON world_objects (quest_instance_id)
  WHERE quest_instance_id IS NOT NULL;
```

`ON DELETE CASCADE` on `quest_instance_id` is a defensive backstop — the `QuestProjector` explicitly deletes quest-scoped objects before the quest_instances row is finalized, so the cascade should never fire in normal operation. It exists for safety during operational repair.

## Semantics

| State | `quest_player_id` | `quest_instance_id` | Notes |
|---|---|---|---|
| Pre-existing public object | NULL | NULL | All current objects |
| Quest-scoped spawned item | set | set | Visible to owner only |
| Reward item (post-finalize) | NULL | NULL | Normal item, in owner's inventory |

The check constraint forbids `(quest_player_id NULL, quest_instance_id set)` and vice versa — they always travel together.

## Viewer filter contract

Two query functions in `AgenticRealms.World.Queries` are extended/added:

### `list_objects_in_room_for_viewer/2` (NEW)

```elixir
@spec list_objects_in_room_for_viewer(room_id :: binary, viewer_player_id :: integer) :: [Object.t()]
def list_objects_in_room_for_viewer(room_id, viewer_player_id) do
  Object
  |> where([o], o.room_id == ^room_id)
  |> where([o], is_nil(o.quest_player_id) or o.quest_player_id == ^viewer_player_id)
  |> order_by(:name)
  |> Repo.all()
end
```

Replaces all room-rendering call sites of `list_objects_in_room/1` (`queries.ex:317–324`). The legacy `list_objects_in_room/1` is retained ONLY for code paths that need the full unfiltered list (e.g., projector cleanup) and gets a `# unsafe for rendering` comment.

### `resolve_object_in_room/2` (EXTENDED)

Existing function at `queries.ex:219–236`. Add the same WHERE predicate so a non-owner cannot resolve a quest-scoped item by name:

```elixir
def resolve_object_in_room(room_id, viewer_player_id, name) do
  Object
  |> where([o], o.room_id == ^room_id)
  |> where([o], is_nil(o.quest_player_id) or o.quest_player_id == ^viewer_player_id)
  |> where([o], fragment("lower(?) = lower(?)", o.name, ^name))
  |> Repo.one()
end
```

Signature changes from `(room_id, name)` → `(room_id, viewer_player_id, name)`. All call sites must be updated to thread the viewer's `player_id` through.

## Call sites to update

- `RoomView` assembly in `Queries.look_room/1` (`queries.ex:36–54`) — pass the viewer's `player_id` to `list_objects_in_room_for_viewer/2`.
- `World.Commands.take/2` — uses `resolve_object_in_room/3` with the player as viewer (player can only take what they can see).
- `World.Commands.examine/*` (and any examine-related path) — same viewer filter applied.

## Inventory rendering

No filter changes. An item is in inventory iff `player_id = $viewer`. The `quest_player_id` field on inventory items is informational only (lets the engine know the item is quest-scoped for cleanup; rendering already restricts by `player_id`).

## Tests (`test/agenticrealms/world/queries_quest_filter_test.exs`)

- `list_objects_in_room_for_viewer/2`: object with `quest_player_id=nil` visible to all; object with `quest_player_id=A` visible to A, hidden from B.
- `resolve_object_in_room/3`: non-owner cannot resolve a quest-scoped item; owner can; public item resolves for both.
- DB check constraint rejects `(quest_player_id IS NULL, quest_instance_id NOT NULL)` and vice versa.
