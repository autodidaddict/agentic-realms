# Contract: `NPCBlueprint` quest-catalog extension

## Schema

Extends the existing `AgenticRealms.World.NPCBlueprint` Ecto schema (`lib/agenticrealms/world/schemas/npc_blueprint.ex`).

```elixir
field :quests, {:array, :map}, default: []
```

Backed by a new `npc_blueprints.quests` column:

```sql
ALTER TABLE npc_blueprints
ADD COLUMN quests jsonb NOT NULL DEFAULT '[]'::jsonb;
```

## Quest catalog entry shape (template-level)

Each element of `quests` is a map with this shape:

```elixir
%{
  "slug" => "golden_apples",
  "title" => "The Orchard Keeper's Errand",
  "narrative" => "Three golden apples have rolled away from my orchard. Bring them back.",
  "criteria" => [
    %{
      "name" => "Golden Apples",
      "quest_tag" => "quest.orchard.golden_apple",
      "target_count" => 3,
      "spawn_room_ids" => ["<room_id_1>", "<room_id_2>", "<room_id_3>"]
    }
  ],
  "reward" => %{
    "name" => "bigger golden apple",
    "description" => "An impossibly large golden apple, warm to the touch."
  }
}
```

JSON-encoded keys are strings (matches jsonb storage and the way the rest of the project encodes maps into jsonb columns).

## Validation rules (enforced in `Commands.create_npc_blueprint/*` wrapper)

| Rule | Error reason |
|---|---|
| `quests` is a list (possibly empty) | `:invalid_quests` |
| Each entry has non-empty `slug` (string) | `:quest_invalid_slug` |
| `slug` values are unique within this blueprint | `:quest_duplicate_slug` |
| Each entry has `title` (non-empty string) | `:quest_invalid_title` |
| Each entry has `narrative` (non-empty string) | `:quest_invalid_narrative` |
| Each entry has `criteria` (list of ≥ 1) | `:quest_no_criteria` |
| Each criterion has non-empty `name`, `quest_tag` (lowercase dot-segmented), `target_count >= 1` | `:quest_invalid_criterion` |
| For each criterion, `length(spawn_room_ids) == target_count` | `:quest_spawn_count_mismatch` |
| Every `spawn_room_id` references an existing room in the read model | `:quest_unknown_spawn_room` |
| Each entry has `reward.name`, `reward.description` (non-empty strings) | `:quest_invalid_reward` |

`Commands.create_npc_blueprint/*` returns `{:error, reason, details}` on any rule violation, without dispatching the `CreateNPCBlueprint` command.

## `NPCBlueprintCreated` event extension

Add a `quests` field to the existing event struct (`lib/agenticrealms/world/events/npc_blueprint_created.ex`):

```elixir
defstruct [
  :blueprint_id,
  :name,
  :short_description,
  :long_description,
  :lore,
  :behaviors,
  :quests        # NEW
]
```

**Replay compatibility**: Existing event JSON serialized before this feature does not contain a `quests` key. The aggregate's `apply/2` clause uses `Map.get(event, :quests, [])` so legacy events default cleanly to `[]`. The projector handler does the same.

## Aggregate

`AgenticRealms.World.NPCBlueprint`:

```elixir
defstruct [
  :id,
  :name,
  :short_description,
  :long_description,
  :lore,
  :behaviors,
  :quests,            # NEW; default []
  :next_serial,
  :clone_ids
]
```

- `execute/2` for `CreateNPCBlueprint` copies the command's `quests` field through.
- `apply/2` for `NPCBlueprintCreated` reads `quests` with the `Map.get(.., [])` legacy-default.

## Projector

`WorldProjector.handle/2` for `NPCBlueprintCreated` extends the existing upsert to include `quests`:

```elixir
%NPCBlueprint{
  id: e.blueprint_id,
  name: e.name,
  short_description: e.short_description,
  long_description: e.long_description,
  lore: Map.get(e, :lore, ""),
  behaviors: Map.get(e, :behaviors, []),
  quests: Map.get(e, :quests, [])
}
|> Repo.insert(on_conflict: :replace_all, conflict_target: :id)
```

## Tests

- `Commands.create_npc_blueprint/*` rejects each validation rule above with the corresponding reason.
- `NPCBlueprint.execute/2` round-trips `quests` through `CreateNPCBlueprint` → `NPCBlueprintCreated`.
- `NPCBlueprint.apply/2` defaults `quests` to `[]` for legacy events.
- `WorldProjector` test inserts a row with a 1-entry catalog and reads it back via Ecto.
