# Commanded Command Contracts: Wizard-Created Object Blueprints (Milestone 1)

Every command in this milestone carries a `wizard_id` field (the originating `players.id`). The `AgenticRealms.World.Commands` wrapper module performs the wizard-authorization check (`is_wizard == true`) before dispatching. Aggregates do NOT re-check authorization; they trust the wrapper.

## `Commands.CreateObjectBlueprint`

```elixir
defmodule AgenticRealms.World.Commands.CreateObjectBlueprint do
  @enforce_keys [:blueprint_id, :wizard_id, :name, :short_description, :long_description]
  defstruct [
    :blueprint_id,
    :wizard_id,
    :name,
    :short_description,
    :long_description,
    kind: "object",
    fixed: false
  ]
end
```

- **Aggregate**: `ObjectBlueprint`.
- **Pre-dispatch wrapper** `Commands.create_object_blueprint/2`:
  1. Authz: refuse if `wizard_id`'s `is_wizard` is `false`.
  2. Slug validation: regex match per FR-007a; reject on shape failure.
  3. Slug-uniqueness pre-check against `object_blueprints` read model: if a row already exists for the slug, return `{:error, :slug_already_exists}` without dispatching (FR-007b — collision surfaced in form, not auto-suffixed).
  4. Dispatch to Commanded.
- **Aggregate behavior**: against `id: nil` state, emits `ObjectBlueprintCreated`. Against initialized state, returns `{:error, :already_exists}` (defense-in-depth — should never happen because of pre-check).
- **Emitted events**: `ObjectBlueprintCreated`.

## `Commands.EditObjectBlueprint`

```elixir
defmodule AgenticRealms.World.Commands.EditObjectBlueprint do
  @enforce_keys [:blueprint_id, :wizard_id, :expected_revision, :fields_changed]
  defstruct [:blueprint_id, :wizard_id, :expected_revision, :fields_changed]
end
```

- **Aggregate**: `ObjectBlueprint`.
- **Pre-dispatch wrapper** `Commands.edit_object_blueprint/3`:
  1. Authz: refuse if not a wizard.
  2. Existence check: refuse if no `object_blueprints` row matches the slug.
  3. Validate `fields_changed` is a map containing only the allowed fields (`:name`, `:short_description`, `:long_description`, `:fixed`).
  4. Dispatch.
- **Aggregate behavior**: matching revision + non-empty diff → `ObjectBlueprintEdited`. Matching revision + empty/no-op diff → `:ok` (no event, FR-008). Mismatched revision → `{:error, :stale_revision, current_revision: N}` (FR-020a).
- **Emitted events**: `ObjectBlueprintEdited` (sometimes none).

## `Commands.SpawnObjectFromBlueprint`

```elixir
defmodule AgenticRealms.World.Commands.SpawnObjectFromBlueprint do
  @enforce_keys [:room_id, :object_id, :blueprint_id, :wizard_id,
                 :name, :short_description, :long_description, :fixed]
  defstruct [
    :room_id,
    :object_id,
    :blueprint_id,
    :wizard_id,
    :name,
    :short_description,
    :long_description,
    :fixed
  ]
end
```

- **Aggregate**: `Room` (the destination room).
- **Pre-dispatch wrapper** `Commands.spawn_object_from_blueprint/3`:
  1. Authz: refuse if not a wizard.
  2. Resolve `blueprint_id` against the `object_blueprints` read model. If absent: `{:error, :unknown_blueprint}`.
  3. Stamp the blueprint's current `name`, `short_description`, `long_description`, `fixed` into the command. (The aggregate cannot read the blueprint — by design — so the wrapper provides the denormalized payload.)
  4. Generate a fresh `object_id` (UUIDv4).
  5. Dispatch.
- **Aggregate behavior**: emits `ObjectSpawned{object_id, room_id, name, short_description, long_description, fixed}`. **`blueprint_id` is NOT in the event** (FR-013, FR-029).
- **Emitted events**: `ObjectSpawned`.

## `Commands.SpawnObjectFreeform`

```elixir
defmodule AgenticRealms.World.Commands.SpawnObjectFreeform do
  @enforce_keys [:room_id, :object_id, :wizard_id,
                 :name, :short_description, :long_description, :fixed]
  defstruct [
    :room_id,
    :object_id,
    :wizard_id,
    :name,
    :short_description,
    :long_description,
    :fixed
  ]
end
```

- **Aggregate**: `Room`.
- **Pre-dispatch wrapper** `Commands.spawn_object_freeform/3`:
  1. Authz: refuse if not a wizard.
  2. Generate `object_id` (UUIDv4).
  3. Dispatch.
- **Aggregate behavior**: emits `ObjectSpawned` with the wizard-supplied payload. Identical event shape to the blueprint path.
- **Emitted events**: `ObjectSpawned`.

## `Commands.EditObject`

```elixir
defmodule AgenticRealms.World.Commands.EditObject do
  @enforce_keys [:room_id, :object_id, :wizard_id, :fields_changed]
  defstruct [:room_id, :object_id, :wizard_id, :fields_changed]
end
```

- **Aggregate**: `Room` (the room currently owning the object).
- **Pre-dispatch wrapper** `Commands.edit_object/3`:
  1. Authz: refuse if not a wizard.
  2. Resolve the object's current location from `world_objects.room_id`. If the object is in a player's inventory or in a different room than the wizard's current room: refuse `{:error, :object_not_editable_here}` (milestone 1 limits in-place edit to objects co-located with the wizard).
  3. Validate `fields_changed` keys against the allowed set (`:name`, `:short_description`, `:long_description`, `:fixed`).
  4. Dispatch.
- **Aggregate behavior**: emits `ObjectEdited{object_id, fields_changed}`. No-op diff returns `:ok` with no event.
- **Emitted events**: `ObjectEdited` (sometimes none).

## `Commands.ExtractObjectEssence` (synthetic wrapper)

Not a Commanded command — a **wrapper-level operation** that orchestrates a read + a `CreateObjectBlueprint` dispatch.

```elixir
@spec extract_object_essence(wizard_id :: integer, source_object_id :: binary_id,
                              proposed_slug :: String.t()) ::
        {:ok, blueprint_id :: String.t()} | {:error, term}
```

Behavior:
1. Authz: refuse if not a wizard.
2. Read `world_objects` row for `source_object_id`. If absent: `{:error, :unknown_object}`.
3. Validate `proposed_slug` per FR-007a; if invalid: `{:error, :invalid_slug}`.
4. Slug-uniqueness check; if collision: `{:error, :slug_already_exists}`.
5. Construct `CreateObjectBlueprint` with the object's `name`, `short_description`, `long_description`, `fixed` wholesale-copied (per Q-extract-wholesale clarification).
6. Dispatch via the same path as `Commands.create_object_blueprint/2`.
7. Return `{:ok, blueprint_id}`.

The source object is NOT modified anywhere in this flow (FR-018).

## `Accounts.promote_to_wizard/1` (non-Commanded)

```elixir
@spec promote_to_wizard(player_id :: integer) ::
        {:ok, %AgenticRealms.Accounts.Player{}} | {:error, :not_found}
```

- Plain Ecto update: `players.is_wizard = true` for the given id.
- Idempotent: re-running against an already-wizard returns `{:ok, player}` with the same shape.
- Returns `{:error, :not_found}` if no row matches.
- Intended invocation: `iex -S mix phx.server` then `AgenticRealms.Accounts.promote_to_wizard(player_id)`.
- No corresponding Commanded command or event (per R1 in research.md).

## Authorization model

All wizard-mode commands pass through `AgenticRealms.World.Commands` wrappers. Each wrapper begins with:

```elixir
defp ensure_wizard(player_id) do
  case Accounts.get_player(player_id) do
    %Accounts.Player{is_wizard: true} -> :ok
    %Accounts.Player{is_wizard: false} -> {:error, :not_a_wizard}
    nil -> {:error, :unknown_player}
  end
end
```

The check is read-synchronous against the `players` read model. LiveView event handlers perform the same check at their entry as a UX gate (per FR-WIZ-4) — a non-wizard who somehow triggers a wizard-only handler is refused without state change.

## Failure mode summary

| Failure                                       | Returned shape                                | Surfaced to user as                                       |
|-----------------------------------------------|-----------------------------------------------|-----------------------------------------------------------|
| Caller not a wizard                           | `{:error, :not_a_wizard}`                     | LiveView refuses earlier; if reached, generic flash       |
| Blueprint slug invalid                        | `{:error, :invalid_slug}`                     | Inline error in slug field of the form                    |
| Blueprint slug collision                      | `{:error, :slug_already_exists}`              | Inline error in slug field; wizard chooses different slug |
| Edit on a stale revision                      | `{:error, :stale_revision, current_revision: N}` | Form reloads with latest values; wizard reapplies edits |
| Edit of an object not in current room         | `{:error, :object_not_editable_here}`         | Inline error or refusal flash                             |
| Edit/spawn of a non-existent target           | `{:error, :unknown_blueprint}` / `:unknown_object` | Generic refusal                                       |
| Empty-diff edit                               | `:ok` (no event)                              | Form closes; no observable state change                   |
