# Contract — Anthropic tool definitions

Defines the tools shipped to the Anthropic Messages API on every intent-resolver request. The list MUST match exactly between the cached tools array sent in the request and the dispatcher's branch table — adding a tool means updating both places.

These tool definitions live in `lib/agenticrealms/world/intent_resolver/tools.ex` as a single module attribute (compile-time constant). The wire format is the JSON shape below; the Elixir module returns the same shape as a list of maps for serialization by `Jason`.

## Tool list

### `take`

```json
{
  "name": "take",
  "description": "Pick up an object that is currently in the player's room and move it into their inventory. Use this when the player wants to acquire, grab, pick up, fetch, take, or otherwise possess an object that is visible in the current room. The `object` argument should be the object's name as the player would refer to it; the game performs case-insensitive matching downstream.",
  "input_schema": {
    "type": "object",
    "properties": {
      "object": {
        "type": "string",
        "description": "The name of the object to take, as the player referred to it (e.g., 'brass lantern', 'lantern', 'the journal'). Case-insensitive."
      }
    },
    "required": ["object"]
  }
}
```

### `drop`

```json
{
  "name": "drop",
  "description": "Drop an object from the player's inventory into the current room. Use this when the player wants to put down, release, let go of, or otherwise relinquish an object they are carrying.",
  "input_schema": {
    "type": "object",
    "properties": {
      "object": {
        "type": "string",
        "description": "The name of the object to drop (must be in the player's inventory). Case-insensitive."
      }
    },
    "required": ["object"]
  }
}
```

### `move`

```json
{
  "name": "move",
  "description": "Move the player through an exit in the current room. Use this when the player wants to go, walk, head, travel, or otherwise change rooms in a specific direction. The direction MUST be one of the six compass/vertical directions; if the player names a target room or non-cardinal direction, refuse instead.",
  "input_schema": {
    "type": "object",
    "properties": {
      "direction": {
        "type": "string",
        "enum": ["north", "south", "east", "west", "up", "down"],
        "description": "One of the six canonical directions."
      }
    },
    "required": ["direction"]
  }
}
```

### `look`

```json
{
  "name": "look",
  "description": "Render the player's current room — its name, description, exits, objects visible, and other players present. Use this ONLY when the player wants to see their surroundings as a whole. DO NOT use this when the player wants to examine, inspect, study, or read a specific object — there is no examine tool yet; use `refuse` with a hint instead.",
  "input_schema": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

### `inventory`

```json
{
  "name": "inventory",
  "description": "List the objects the player is currently carrying. Use this when the player asks what they have, what's in their pockets, their inventory, their stuff, etc.",
  "input_schema": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

### `say`

```json
{
  "name": "say",
  "description": "Broadcast a spoken utterance to every player currently in the same room as the speaker. Use this when the player wants to speak aloud, talk, say something out loud, or address everyone in the room. The `text` argument should be the spoken content with the player's original casing preserved.",
  "input_schema": {
    "type": "object",
    "properties": {
      "text": {
        "type": "string",
        "description": "The exact text the player wants to speak. Preserve their casing and punctuation."
      }
    },
    "required": ["text"]
  }
}
```

### `emote`

```json
{
  "name": "emote",
  "description": "Perform a third-person narrative action visible to everyone in the room, including the actor. Use this when the player describes an action they are taking (waving, bowing, smiling, gesturing) rather than speaking. The narration will be rendered as '<player name> <text>'.",
  "input_schema": {
    "type": "object",
    "properties": {
      "text": {
        "type": "string",
        "description": "The action verb phrase, third-person present-tense without the actor's name (e.g., 'waves at the fire', 'bows deeply')."
      }
    },
    "required": ["text"]
  }
}
```

### `tell`

```json
{
  "name": "tell",
  "description": "Send a private message to a named player who can be anywhere in the world (any room, online). Use this when the player wants to message, contact, DM, send a note to, or tell a specific named player something. Cross-room delivery is fine — `tell` works regardless of where the recipient is.",
  "input_schema": {
    "type": "object",
    "properties": {
      "recipient": {
        "type": "string",
        "description": "The recipient's display name (username). Case-insensitive; downstream resolution handles matching."
      },
      "text": {
        "type": "string",
        "description": "The private message text."
      }
    },
    "required": ["recipient", "text"]
  }
}
```

### `whisper`

```json
{
  "name": "whisper",
  "description": "Send a private message to a named player who is in the SAME room as the speaker. Use this when the player wants to whisper, mutter aside, lean in close to, or speak privately with someone nearby. If the recipient is in a different room, the game will refuse — use `tell` for cross-room private messages.",
  "input_schema": {
    "type": "object",
    "properties": {
      "recipient": {
        "type": "string",
        "description": "The recipient's display name. They must be in the same room."
      },
      "text": {
        "type": "string",
        "description": "The whispered message text."
      }
    },
    "required": ["recipient", "text"]
  }
}
```

### `refuse`

```json
{
  "name": "refuse",
  "description": "Decline to act on the player's input because it doesn't map to a supported action. Use this when: (a) the player's intent is out of game scope ('what time is it?', 'save my game'); (b) the intent is for a future action not yet supported (combat, magic, examining specific objects, reading); (c) the intent is multi-step (e.g., 'take the lantern and go north' — only one action per turn is allowed in this version, refuse with a hint to chain manually); (d) the intent is too ambiguous to act on confidently; (e) the player's input is nonsense or in a non-English language. The `message` field is the player-facing refusal — write it in a brief, helpful tone that tells the player what the game CAN do when relevant.",
  "input_schema": {
    "type": "object",
    "properties": {
      "message": {
        "type": "string",
        "description": "The refusal message the player will see in their narrative log. Brief (one or two sentences). Friendly. When refusing due to a missing action, hint at what IS supported (e.g., 'You can `look` to see the room, but examining specific objects isn't supported yet.'). Do NOT include internal jargon like 'LLM', 'tool', 'API'."
      }
    },
    "required": ["message"]
  }
}
```

## Tool ordering and cache marker placement (implementation-corrected)

The tools array is shipped in the order above with **no `cache_control` on any tool**. The cache marker lives on the **system block** instead — render order is `tools → system → messages`, so a marker on the system block caches the tools array + system prompt together; a marker on the last tool would cache only the tools. See `contracts/system_prompt.md` for the marker and the note that caching does not engage at the current prompt size (Haiku 4.5's 4096-token minimum vs. ~2000–2500 tokens of system + tools).

## Validation rules at the dispatcher

After receiving the response, the dispatcher (in `World.IntentResolver`) validates the tool call:

1. **Tool name is in the expected set**: one of the 10 names above. Unknown → uniform refusal.
2. **Required fields present**: per the schema above. Missing → uniform refusal.
3. **Direction enum** (for `move`): one of the 6 strings. The API should reject this server-side via the schema, but we double-check defensively.
4. **String fields non-empty**: empty `object`, `text`, `recipient`, or `message` → uniform refusal.
5. **Exactly one tool_use block**: multiple → "Try one action at a time."

The validated tool call is then transformed into the action tuple from `data-model.md` Entity 5 and returned.

## Adding a new tool later

When a new canonical action is added to the game (e.g., `examine`, `attack`):

1. Add a new entry to `lib/agenticrealms/world/intent_resolver/tools.ex` with a description and input_schema.
2. Add a dispatch branch in `World.IntentResolver` that maps the new tool to an action tuple shape.
3. Add a `GameLive` `handle_event`/`handle_info` branch that consumes that action tuple shape — same pattern as the existing 9.
4. Update the system prompt's few-shot examples to demonstrate when to use the new tool vs. refuse.

The 5-minute prompt cache will be invalidated on the next deploy (the system prompt changed). No client-side migration needed.
