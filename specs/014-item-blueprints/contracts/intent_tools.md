# LLM Intent Tool Contracts: Wizard-Created Object Blueprints (Milestone 1)

The existing `AgenticRealms.World.IntentResolver` from feature 005 is extended with wizard-mode tools. Tool selection is determined per-invocation by the actor's role and `authoring_mode`:

| Actor role | Authoring mode  | Tool set                                                                                          |
|------------|-----------------|---------------------------------------------------------------------------------------------------|
| Player     | (n/a)           | Existing player tools (unchanged from feature 005).                                               |
| Wizard     | `:world`        | Existing player tools **plus** `manifest_object_freeform`, `spawn_object_from_blueprint`.         |
| Wizard     | `:blueprints`   | `draft_object_blueprint` **only**. Spatial tools refused with a hint (FR-024).                    |

The `IntentResolver`'s `ContextSnapshot` (existing) is extended with three new fields used by the wizard-mode tools:

```elixir
%ContextSnapshot{
  # ... existing fields (player_id, room_id, room_payload, etc.)
  authoring_mode: :world | :blueprints,   # NEW
  focused_object_id: binary_id() | nil,   # NEW
  focused_blueprint_id: String.t() | nil  # NEW
}
```

The `Extract essence` action does NOT have a corresponding LLM tool. It is exclusively triggered by the UI button on a focused world object (FR-022).

## Tool: `manifest_object_freeform`

**When available**: wizard, `:world` mode.

**Purpose**: route a wizard's prompt that describes a new object into a `SpawnObjectFreeform` command for the wizard's current room.

**Anthropic tool schema**:

```json
{
  "name": "manifest_object_freeform",
  "description": "Speak a brand-new object into being in the wizard's current room. Use when the wizard's prompt describes a single, concrete object that should exist as a one-off (not a reusable archetype). Do NOT use to edit an existing object.",
  "input_schema": {
    "type": "object",
    "required": ["name", "short_description", "long_description"],
    "properties": {
      "name": {
        "type": "string",
        "description": "Short, lowercase name (1–4 words)."
      },
      "short_description": {
        "type": "string",
        "description": "A single line shown in room listings."
      },
      "long_description": {
        "type": "string",
        "description": "The full prose shown when a player examines the object."
      },
      "fixed": {
        "type": "boolean",
        "description": "True if the object cannot be picked up by players (e.g., furniture). Default false."
      }
    }
  }
}
```

**Server-side dispatch**: the resolver pulls `room_id` from `ContextSnapshot`, generates an `object_id` (UUIDv4), and dispatches `Commands.SpawnObjectFreeform`. The Interpreted Data card subscribes to the resolver's progressive-fields output and renders fields as they arrive.

## Tool: `spawn_object_from_blueprint`

**When available**: wizard, `:world` mode.

**Purpose**: route a wizard's prompt that references an existing blueprint into a `SpawnObjectFromBlueprint` command.

**Anthropic tool schema**:

```json
{
  "name": "spawn_object_from_blueprint",
  "description": "Spawn a copy of an existing object blueprint into the wizard's current room. Use when the wizard's prompt names or describes something that matches an existing blueprint in the registry (e.g., 'place an iron lantern here').",
  "input_schema": {
    "type": "object",
    "required": ["blueprint_id"],
    "properties": {
      "blueprint_id": {
        "type": "string",
        "description": "The slug of the blueprint to spawn from. Match the registry; do not invent."
      }
    }
  }
}
```

**Server-side dispatch**: the resolver validates `blueprint_id` exists in the `object_blueprints` read model; if not, returns a refusal hint to the LiveView. Otherwise dispatches `Commands.spawn_object_from_blueprint/3` which performs the field-stamping per `contracts/commands.md`.

## Tool: `draft_object_blueprint`

**When available**: wizard, `:blueprints` mode.

**Purpose**: route a wizard's prompt that describes a new archetype into a `CreateObjectBlueprint` command, draft state.

**Anthropic tool schema**:

```json
{
  "name": "draft_object_blueprint",
  "description": "Draft a new object archetype (blueprint) in the wizard's sanctum. Use when the wizard's prompt describes a kind of thing meant to be reused, not a specific one-off in the world.",
  "input_schema": {
    "type": "object",
    "required": ["name", "short_description", "long_description"],
    "properties": {
      "name": {
        "type": "string",
        "description": "Short, lowercase name (1–4 words)."
      },
      "proposed_slug": {
        "type": "string",
        "description": "Optional override for the auto-derived slug. Must match ^[a-z][a-z0-9_]*$, length 1–64."
      },
      "short_description": {"type": "string"},
      "long_description": {"type": "string"},
      "fixed": {
        "type": "boolean",
        "description": "Default false."
      }
    }
  }
}
```

**Server-side handling**: the resolver does NOT dispatch `CreateObjectBlueprint` directly. Instead it returns a *draft* to the LiveView: the wizard sees fields populated in the Interpreted Data card and can refine them via form controls before clicking Commit. Commit dispatches `Commands.create_object_blueprint/2` with the form's current values, auto-deriving the slug from `name` if `proposed_slug` was not supplied (FR-007b).

## Refused / disallowed tools

- **Edit verbs** of any shape are NOT exposed in the tool set in either mode (FR-025). A prompt like "rename the goblin" produces a non-actionable resolver response with a hint that edits happen via the form. The LiveView surfaces the hint inline below the prompt textarea.
- **Spatial tools in `:blueprints` mode** — if the resolver receives a tool call from the LLM that requires `room_id` while `authoring_mode == :blueprints`, it MUST refuse with `{:error, :spatial_tool_in_trance}` and surface a hint that spatial actions aren't available in trance (FR-024).
- **Extract essence** has no LLM tool — UI-button only (FR-022).
- **Delete tools** of any kind — there is no `delete_object`, `delete_object_blueprint`, etc. (per Q2).

## Failure modes

| LLM-side outcome                                                          | Resolver / LiveView behavior                                                                 |
|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| LLM returns no tool call (e.g., conversational reply)                     | Resolver returns `{:refused, :no_actionable_intent}`; LiveView leaves the Commit button disabled and surfaces an inline "I couldn't extract a creation intent — try rephrasing or use the form directly" hint. |
| LLM returns a tool call requiring `room_id` in `:blueprints` mode         | Resolver refuses with `:spatial_tool_in_trance`; LiveView shows "Spatial actions aren't available in the sanctum — return to your body to manifest things." |
| LLM returns `spawn_object_from_blueprint` with an unknown `blueprint_id`  | Resolver refuses with `:unknown_blueprint`; LiveView shows "I don't have a blueprint by that name in the registry yet." |
| LLM returns a tool call with an invalid `proposed_slug`                   | Resolver refuses with `:invalid_slug`; LiveView shows the regex constraint inline.           |
| LLM upstream error / timeout                                              | Resolver returns the existing feature-005 error shape; LiveView keeps the form editable so the wizard can author by hand. |

## Context-snapshot extensions

The existing `ContextSnapshot` (built by `AgenticRealms.World.IntentResolver.ContextSnapshot`) gains the three new fields shown at the top of this document. They are populated:

- `authoring_mode` from the LiveView socket assigns at the moment of prompt submit.
- `focused_object_id` from the assigns when the wizard has a world Object focused; otherwise `nil`.
- `focused_blueprint_id` from the assigns when the wizard has a Blueprint focused (in `:blueprints` mode); otherwise `nil`.

Tools may read these but milestone 1's tools do not USE `focused_*_id` — they are populated for telemetry and forward-compatibility with milestone 2.
