# Data Model: NPC Conversations (Feature 010)

## 1. Persistent additions

### 1.1 `NPCBlueprint.lore` (new column)

| Attribute   | Value                                                                |
|-------------|----------------------------------------------------------------------|
| Column name | `lore`                                                               |
| Type        | `text`                                                               |
| Constraints | `NOT NULL DEFAULT ''`                                                |
| Audience    | LLM only — fed into the system prompt as the NPC's voice/backstory.  |
| Wizard UX   | Authored at blueprint creation; seed-only authoring in this feature. |
| Inheritance | Full-copy to clones at spawn time (same as `behaviors` in 009).      |
| Length cap  | No hard DB cap; if a single lore string exceeds practical token budgets, the implementation may truncate at LLM call time (see FR-019c). |

### 1.2 `NPCClone.lore` (new column)

| Attribute   | Value                                                                |
|-------------|----------------------------------------------------------------------|
| Column name | `lore`                                                               |
| Type        | `text`                                                               |
| Constraints | `NOT NULL DEFAULT ''`                                                |
| Population  | Copied verbatim from the source blueprint's `lore` at `NPCClonedFromBlueprint` time. |
| Mutability  | Immutable post-clone in this feature (no per-clone lore override yet).|

### 1.3 Event extensions (backward-compatible)

Three event/command structs add a `lore: ""` field to their defstruct (NOT in `@enforce_keys`). Old payloads deserialize with `lore = ""`.

- `AgenticRealms.World.Commands.CreateNPCBlueprint` — `field :lore, :string, default: ""`
- `AgenticRealms.World.Events.NPCBlueprintCreated` — `field :lore, :string, default: ""`
- `AgenticRealms.World.Events.NPCClonedFromBlueprint` — `field :lore, :string, default: ""`

### 1.4 Migration: `add_lore_columns.exs`

```elixir
defmodule AgenticRealms.Repo.Migrations.AddLoreColumns do
  use Ecto.Migration

  def change do
    alter table(:npc_blueprints) do
      add :lore, :text, null: false, default: ""
    end

    alter table(:npc_clones) do
      add :lore, :text, null: false, default: ""
    end
  end
end
```

No index. No foreign key. Plain text column.

---

## 2. Volatile (non-persistent) entities

### 2.1 `AgenticRealms.World.NPCChat.Conversation` (GenServer state)

| Field           | Type                                                            | Notes |
|-----------------|-----------------------------------------------------------------|-------|
| `player_id`     | `integer()`                                                     | The chatting player. Half of the registry key. |
| `npc_clone_id`  | `String.t()` (UUID-like)                                        | The targeted NPC clone. Other half of the registry key. |
| `npc_name`      | `String.t()`                                                    | The clone's `name` (e.g., "Garrick the Innkeeper"). Cached at init to avoid re-querying. |
| `lore`          | `String.t()`                                                    | Cached at init from the clone's `lore` field. May be `""`. |
| `turns`         | `[%{role: :player | :npc, text: String.t(), mode: :speech | :emote | nil}]` | Rolling 20-turn history. Player turns have `mode: nil`. Newest at the tail. |
| `last_activity_at` | `integer()` (monotonic ms)                                    | Updated on every `:send` call. Used to render the new-vs-continuing indicator. (The `:timeout` mechanism uses the runtime's idle clock — not this field.) |
| `pending?`      | `boolean()`                                                     | `true` between dispatch of an LLM Task and arrival of `{:llm_result, ...}`. Drives FR-020's per-pair lockout. |
| `pending_player_message` | `String.t() | nil`                                     | The player utterance that's currently in flight. Held out-of-band so the failure path (FR-011) can discard it without polluting `turns`. |
| `task_ref`      | `reference() | nil`                                             | The reference returned by `Task.Supervisor.async_nolink/2`. Used to discard stale results if the GenServer terminates and a Task somehow survives. |

#### State transitions

```text
idle (no in-flight call)
  │
  ├─ :send call arrives, input valid, NPC matches
  │     │
  │     ├─ pending? == false:
  │     │    set pending? = true
  │     │    set pending_player_message = msg
  │     │    update last_activity_at
  │     │    dispatch Task → Anthropic
  │     │    reply {:ok, :new | :continuing}    ←  computed from age of last_activity_at
  │     │    state stays "pending"
  │     │
  │     └─ pending? == true:
  │           reply {:error, :still_thinking}    ←  FR-020 rejection
  │           state unchanged
  │
  └─ :timeout (no message for 60s):
        {:stop, :normal, state}
        Horde reaps the registry entry

pending (one in-flight call)
  │
  ├─ :send call arrives → {:error, :still_thinking}
  │
  ├─ {:llm_result, {:ok, %{mode: m, text: t}}} arrives:
  │     append %{role: :player, text: pending_player_message} to turns
  │     append %{role: :npc, text: t, mode: m} to turns
  │     trim turns to most-recent 20 pairs
  │     broadcast ChatUtterance{kind: :chat_speech | :chat_emote} on player_topic
  │     clear pending?, pending_player_message, task_ref
  │     state → idle
  │
  └─ {:llm_result, {:error, _}} arrives  (or :DOWN with non-:normal reason):
        DO NOT append pending_player_message to turns (FR-011)
        broadcast ChatSystemMessage{kind: :chat_fallback} on player_topic
        clear pending?, pending_player_message, task_ref
        state → idle
```

#### Lifecycle

- **Spawn**: `Horde.DynamicSupervisor.start_child/2` on first `NPCChat.send/3` for the pair, with the conversation registered under `{:via, Horde.Registry, {NPCChat.Registry, {player_id, npc_clone_id}}}`.
- **Lookup**: Subsequent calls find the existing pid via the registry; no spawn.
- **Termination**: Normal `{:stop, :normal, state}` on idle timeout. Horde reaps. No surviving artifacts.

---

### 2.2 `AgenticRealms.World.UIEvents.ChatUtterance` (transient UI event)

Mirrors feature 009's `BehaviorUtterance` but on the private surface.

```elixir
defstruct [
  :kind,              # :chat_speech | :chat_emote
  :npc_clone_id,
  :npc_name,
  :text,
  :triggering_player_id
]
```

Broadcast on `World.player_topic(triggering_player_id)` — never on `room_topic`.

### 2.3 `AgenticRealms.World.UIEvents.ChatSystemMessage` (transient UI event)

For the system messages that frame the chat (FR-003 indicator, FR-020 rejection, FR-011 fallback).

```elixir
defstruct [
  :kind,              # :chat_new | :chat_continuing | :chat_in_flight_rejection | :chat_fallback
  :npc_name,
  :text,              # rendered final text
  :player_id
]
```

Same delivery surface (`player_topic`).

---

## 3. Identity and uniqueness

- **Conversation key** = `{player_id, npc_clone_id}`. Uniqueness enforced by `Horde.Registry` `keys: :unique`.
- The blueprint id is NOT part of the key — `{Alice, Garrick#1}` and `{Alice, Garrick#2}` are distinct conversations (per the spec's "One conversation per (player, NPC clone) pair" assumption).
- After a Conversation idles out, the registry entry is removed. A new `NPCChat.send/3` for the same pair starts a fresh Conversation with empty history.

## 4. Relationships

```text
NPCBlueprint  1 ── * NPCClone    (existing, feature 008)
                      │
                      │ (cached at init time)
                      ▼
            NPCChat.Conversation
                      │
                      │ broadcasts via PubSub
                      ▼
              ChatUtterance, ChatSystemMessage  →  GameLive (player-topic subscriber)
```

No NPCClone-to-Conversation foreign key — the Conversation only stores the clone id and the cached name+lore at init. If the clone is despawned between turns, the next `NPCChat.send/3` fails at the resolution step (the LiveView's room state no longer contains that clone), and the dangling Conversation idles out.

## 5. Validation rules

- **Per-utterance length**: `String.length(message) ∈ [1, 500]`. Enforced in `NPCChat.send/3` before dispatch.
- **Lore length**: no DB cap, but the assembled-context budget (FR-019c) may truncate during prompt assembly. The implementation logs a warning when lore alone exceeds 4000 chars.
- **NPC name resolution**: reuses feature 006's `Examine.resolve/2` rules — case-insensitive substring match on the clone's `name`; ambiguity returns the standard disambiguation error.
- **Conversation history trim**: after each successful turn, `length(turns) <= 40` (20 pairs of player+NPC entries).

## 6. Data volume / scale

- Per-conversation memory: ~few KB worst case (20 turns × ~1000 chars/turn + lore ≤ 4000 chars + cached name).
- Concurrent conversations: cluster-wide, bounded by player count × number of chattable NPCs in their rooms. Expected ~10–100 in early playtest.
- Idle reap interval: BEAM runtime delivers `:timeout` deterministically; no separate sweeper.

## 7. Non-data invariants

- **No domain events**: this feature does NOT emit events on the EventStore. The lore plumbing IS event-sourced (because `lore` lives on the persistent blueprint/clone), but Conversations and turns are not.
- **No survival across restart**: a server restart drops all Conversation state. Players will see "new conversation" on their next chat. Acceptable per FR-014.
- **Privacy invariant**: `ChatUtterance` and `ChatSystemMessage` MUST never be broadcast on a `room_topic` or any other player's `player_topic`. Verified by the SC-007 integration audit.
