# Data Model: GUI Design Language

**Feature**: 001-gui-design-language  
**Date**: 2026-04-22  
**Note**: All data is mocked (static Elixir maps). No database tables or Ecto schemas.

## Entities

### Room

Represents a location in the game world.

| Field | Type | Description |
|-------|------|-------------|
| id | atom | Unique room identifier (e.g., `:tavern`) |
| name | string | Display name (e.g., "The Gilded Kraken") |
| coord | string | Grid coordinate (e.g., "3,2") |
| desc | string | Room description prose |
| exits | list of Exit | Directional exits to other rooms |
| entities | list of Entity | NPCs, items, players present |

### Exit

| Field | Type | Description |
|-------|------|-------------|
| dir | string | Direction (e.g., "north", "east", "down") |
| to | string | Destination name |

### Entity (Room Presence)

| Field | Type | Description |
|-------|------|-------------|
| name | string | Display name |
| type | string | One of: "npc", "item", "player-other" |

### LogEntry

A single entry in the player's narrative log.

| Field | Type | Description |
|-------|------|-------------|
| kind | atom | One of: `:room`, `:narrate`, `:cmd`, `:said`, `:whisper`, `:system`, `:combat` |
| text | string | Entry text (for non-room entries) |
| room | Room | Room data (only for `:room` kind) |
| who | string | Speaker name (only for `:said` kind) |
| dmg | integer | Damage number (only for `:combat` kind) |
| pct | float | HP bar percentage (only for `:combat` kind) |

### PlayerStats

| Field | Type | Description |
|-------|------|-------------|
| name | string | Character name |
| class | string | Class and level (e.g., "Cleric · lvl 7") |
| hp | map | `%{cur: integer, max: integer}` |
| mp | map | `%{cur: integer, max: integer}` |
| xp | map | `%{cur: integer, max: integer}` |

### InventoryItem

| Field | Type | Description |
|-------|------|-------------|
| name | string | Item name |
| qty | integer | Quantity |
| equipped | boolean | Whether currently equipped |

### Quest (Player View)

| Field | Type | Description |
|-------|------|-------------|
| title | string | Quest name |
| progress | string | Current progress description |

### QuestDetail (Modal View)

| Field | Type | Description |
|-------|------|-------------|
| title | string | Quest name |
| giver | string | NPC who gave the quest |
| synopsis | string | Brief synopsis |
| desc | string | Full description |
| steps | list of QuestStep | Ordered steps |
| rewards | list of string | Reward descriptions |

### QuestStep

| Field | Type | Description |
|-------|------|-------------|
| t | string | Step description |
| done | boolean | Completion status |

### PresenceEntry

| Field | Type | Description |
|-------|------|-------------|
| name | string | Entity name |
| status | string | "active" or "idle" |
| npc | boolean | Whether this is an NPC (default false) |

### MapNode

| Field | Type | Description |
|-------|------|-------------|
| id | string | Node identifier |
| x | integer | X position (percentage) |
| y | integer | Y position (percentage) |
| label | string | Short label |
| state | string | "current", "visited", or "unvisited" |

### MapEdge

A tuple `{from_id, to_id}` connecting two map nodes.

---

## Wizard Data Model

### WizardExample

Template data for each content kind in the wizard editor.

| Field | Type | Description |
|-------|------|-------------|
| kind | string | Content type (e.g., "Room", "NPC", "Item", "Quest") |
| icon | string | Emoji icon for header |
| slug | string | URL-style path identifier |
| title | string | Display title |
| fields | list of WizardField | Ordered data fields |
| triggers | list of Trigger | Behavioral triggers (optional) |
| ingame | string | HTML string for in-game preview (optional) |

### WizardField

| Field | Type | Description |
|-------|------|-------------|
| k | string | Field label key |
| v | string | Field value (for simple types) |
| kind | string | Render type: "prose", "tag", "tags", "num", "exits", "entities", "stats", "loot", "adjectives", "steps", "rewards" |
| items | list | Items for "tags", "adjectives" kinds |
| exits | list of Exit | For "exits" kind |
| entities | list | For "entities" kind |
| stats | list of StatEntry | For "stats" kind |
| steps | list of StepEntry | For "steps" kind |
| rewards | list of RewardEntry | For "rewards" kind |
| note | string | Optional note text (for "adjectives" kind) |

### StatEntry

| Field | Type | Description |
|-------|------|-------------|
| k | string | Stat name |
| v | string | Stat value |
| sub | string | Modifier (optional, e.g., "+2") |

### StepEntry

| Field | Type | Description |
|-------|------|-------------|
| id | string | Step identifier |
| desc | string | Player-facing description |

### RewardEntry

| Field | Type | Description |
|-------|------|-------------|
| kind | string | Reward type: "item", "xp", "faction" |
| value | string | Reward value/ID |
| label | string | Human-readable label (optional) |

### LootEntry

| Field | Type | Description |
|-------|------|-------------|
| name | string | Item name |
| chance | integer | Drop percentage (0-100) |

### Trigger

| Field | Type | Description |
|-------|------|-------------|
| id | string | Trigger identifier |
| intent | string | Intent type (e.g., "Use", "Take", "Whisper") |
| note | string | Description of when/why trigger fires |
| conditions | list of Condition | All must be true for trigger to fire |
| actions | list of Action | Ordered actions to execute |

### Condition

| Field | Type | Description |
|-------|------|-------------|
| subject | string | What to evaluate (e.g., "room.light", "player.stealth") |
| op | string | Operator: "equals", "not_equals", "has_tag", "not_has_flag", "gte", "lte", "contains" |
| value | string or number | Expected value |

### Action

| Field | Type | Description |
|-------|------|-------------|
| kind | string | Action type: "emit_text", "modify_prop", "spawn_entity", "set_disposition", "grant_item", "require_input" |
| target | string | Target entity ID (optional) |
| scope | string | "room" or "player" (for emit_text) |
| text | string | Text content (for emit_text) |
| prop | string | Property name (for modify_prop) |
| value | string | Value to set |
| attrs | string | Attributes (for spawn_entity) |
| prompt | string | Prompt text (for require_input) |

---

## Tweaks (User Preferences)

| Field | Type | Values | Default |
|-------|------|--------|---------|
| theme | string | "phosphor", "paper", "dusk" | "phosphor" |
| density | string | "comfortable", "compact" | "comfortable" |
| player_layout | string | "classic", "panels", "minimal" | "classic" |
| wizard_preview | string | "card", "ingame" | "card" |
| show_hud | boolean | true, false | true |

---

## Relationships

```
Room --has many--> Exit
Room --has many--> Entity
Room --has many--> Trigger (optional)
WizardExample --has many--> WizardField
WizardExample --has many--> Trigger (optional)
Trigger --has many--> Condition
Trigger --has many--> Action
PlayerStats --used by--> HUD Card (Character)
InventoryItem --used by--> HUD Card (Inventory)
Quest --used by--> HUD Card (Quest Log)
QuestDetail --used by--> Quest Modal
PresenceEntry --used by--> HUD Card (Present)
```

## State Transitions

No persistent state transitions — all data is static/mocked. The only runtime state changes are:

- `mode`: player ↔ wizard (via topbar toggle)
- `modal`: nil → "stats" | "inv" | "quests" | "presence" | trigger → nil
- `map_open`: true ↔ false (via map toggle)
- `log`: append-only list (new entries added on command submit)
- `wizard_kind`: room | npc | item | quest | spell (via kind picker)
- `wizard_text`: string (textarea content)
- `tweaks`: map (theme/density/layout preferences)
