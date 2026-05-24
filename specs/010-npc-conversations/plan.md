# Implementation Plan: NPC Conversations

**Branch**: `010-npc-conversations` | **Date**: 2026-05-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/010-npc-conversations/spec.md`

## Summary

Players can hold a private, in-character chat with any NPC in their current room via a new `chat <npc> <message>` verb. Each `(player, NPC clone)` pair owns its own short-lived **GenServer process** — `AgenticRealms.World.NPCChat.Conversation` — that holds the rolling 20-turn history, fronts the Anthropic call, enforces the in-flight lockout, and self-terminates after 60s of idleness using the built-in GenServer idle-timeout. Discovery is cluster-aware via **Horde** (`Horde.Registry` for `(player_id, npc_clone_id)` keys, `Horde.DynamicSupervisor` for distributed lifecycle) so that conversations survive node coalescing and reconnects to a different node land on the existing process when it's still alive. No domain events; nothing persisted; everything dies at idle.

The LLM call uses the same Anthropic Messages API client as feature 005's intent resolver, with **tool-use enforced structured output**: two tools (`say` and `emote`), `tool_choice: any`, so each reply is unambiguously a structured speech or emote choice (FR-021). The system prompt lives in a dedicated module `AgenticRealms.World.NPCChat.SystemPrompt` so developers can `grep` for it directly. Per-reply token budget (256) and per-utterance length cap (500 chars) cap cost; the assembled prompt is trimmed by evicting oldest history if needed.

Rendering uses a NEW private UI event `ChatUtterance` broadcast only on the chatting player's `player_topic` — distinct from feature 009's public `:npc_speech`. Other players see nothing of the exchange (FR-017).

## Technical Context

**Language/Version**: Elixir 1.15+ on OTP 26+ (existing project baseline; no change).  
**Primary Dependencies (existing, reused)**:
- `phoenix ~> 1.8`, `phoenix_live_view ~> 1.1.0` — UI layer, command routing
- `commanded ~> 1.4` + `commanded_eventstore_adapter ~> 1.4` — NOT used for chat (no events emitted); used elsewhere in the world
- `phoenix_pubsub` (transitive) — cluster-aware broadcast for the private `ChatUtterance` delivery
- `dns_cluster ~> 0.2.0` — cluster-wide node discovery (already wired)
- `req ~> 0.5` — HTTP client used by `AgenticRealms.Anthropic`
- `jason ~> 1.2` — JSON encoding
- `bandit ~> 1.5` — HTTP server

**Primary Dependencies (new)**:
- `horde ~> 0.9` (or current stable) — distributed `Horde.Registry` and `Horde.DynamicSupervisor` for cluster-native discovery and supervision of `Conversation` GenServers. The user's planning input explicitly requires cluster-friendly discovery; Horde is the canonical Elixir pattern for this exact use case (per-key dynamic processes that need to be looked up from any node) and avoids `:global`'s name-lock scalability ceiling. CRDT-backed registry tolerates node joins/leaves.

**Reused project infrastructure**:
- `AgenticRealms.Anthropic` — already wraps the Messages API with timeouts, error mapping, and `Req.Test` plug hookup for tests (so chat tests don't hit the network).
- `AgenticRealms.IntentResolverTaskSupervisor` (Task.Supervisor) — precedent for fire-and-forget LLM tasks. This feature adds a parallel `AgenticRealms.World.NPCChat.TaskSupervisor` so chat tasks are isolated from intent-parser tasks (so a flood of one doesn't starve the other).
- `AgenticRealms.World.Queries` — `look_room/1`, `list_npcs_in_room/1`, `other_occupants_of/2` provide all the read-side data needed for the context bundle.
- `AgenticRealms.World.Schemas.NPCBlueprint` and `NPCClone` — `lore` field added here (full-copy inheritance via feature 008's pattern, exactly like `behaviors` in feature 009).
- `Phoenix.PubSub` + `AgenticRealms.World.player_topic/1` — cluster-aware private delivery (same path used for feature 009's `BehaviorUtterance` on the broadcast side; this feature uses it only for the chatting player).
- `AgenticRealms.World.UIEvents` — module pattern from feature 009 for transient render-only UI events; `ChatUtterance` lives here.

**Storage**:
- **Conversation history**: in-memory GenServer state ONLY. Not persisted. Not visible to admin tooling.
- **NPC lore**: persistent — added as a new `lore` text column on `npc_blueprints` and `npc_clones` tables via the same migration approach used in feature 008/009 (Ecto schema + JSONB/text column + read-side projection).
- **No new domain events** — feature 010 does not extend the event sourcing layer. Lore additions DO go through events because they're part of NPCBlueprintCreated and NPCClonedFromBlueprint (feature 008 events) — extending those payloads, not adding new events.

**Testing**:
- `ExUnit` (existing) — unit, contract, integration tests.
- `Req.Test` plug (existing pattern from feature 005) — every test that exercises the LLM path injects a stubbed plug via `:req_options` so no real network call leaves the BEAM. The plug returns canned `tool_use` blocks to exercise speech vs. emote vs. failure paths.
- `AgenticRealmsWeb.ConnCase` / `Phoenix.LiveViewTest` — LiveView integration tests for the end-to-end command → reply rendering flow.
- The integration test follows the feature 009 pattern: one comprehensive `@moduletag :integration` test that exercises US1–US5 in sequence, so the test process can share a seeded world and accumulate state.

**Target Platform**: Linux server BEAM cluster (production deploy); macOS BEAM single-node (development). Tests run on developer machines and CI.

**Project Type**: Phoenix LiveView web application (single project structure, no separate backend/frontend split).

**Performance Goals**:
- A single chat turn end-to-end (player command → reply rendered) MUST complete within 15 seconds under normal LLM latency (SC-001 in spec). Internally: LLM call expected ~1–3s, context assembly + dispatch ~10ms.
- The Conversation GenServer's idle timeout (60s) MUST trigger termination promptly; the next chat to the same NPC after that MUST report "new conversation" within 70 seconds of the last turn (SC-005).
- A flood of chat commands from a single player to a single NPC MUST be bounded by FR-020 (per-pair single-in-flight). A flood across many pairs is bounded only by the Task.Supervisor / Anthropic rate limits — out of scope to harden further in this feature.

**Constraints**:
- **No domain events emitted for chats** — purely ephemeral; survives no server restart (FR-014).
- **Privacy** — the chat exchange MUST never leak onto another player's `player_topic` or onto any `room_topic` (FR-017). Verified by the SC-007 zero-leak audit across mixed speech/emote replies.
- **Cluster-correct** — `(player_id, npc_clone_id)` resolution MUST find an existing Conversation regardless of which node it lives on (per user planning input). This rules out `Registry` (local-only); it admits `:global`, `Horde.Registry`, or a custom PubSub-based routing. Horde is the chosen pattern (see research.md).
- **Discoverability** — the system prompt MUST live in a top-of-tree module that's grep-able by name: `AgenticRealms.World.NPCChat.SystemPrompt` (per user planning input).
- **Token budget** — assembled prompt + per-reply cap bounded per FR-019.

**Scale/Scope**:
- Expected concurrent chats: ~10–100 active at a time in early playtest, scaling with player count.
- Conversation lifetime: bounded by 60s idle timeout + 20-turn cap → upper bound of ~20 minutes for a maximally-active conversation (worst case if a player chats once every 59s for 20 turns).
- Per-conversation memory: <10KB (a few KB of text history + small overhead).

## Constitution Check

**Constitution file**: `.specify/memory/constitution.md` is still at template defaults (no concrete principles ratified). There are no enumerated gates to evaluate. Treat as `PASS` by default; no violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/010-npc-conversations/
├── plan.md                    # This file
├── research.md                # Phase 0 — Horde vs :global; tool-use vs JSON output; etc.
├── data-model.md              # Phase 1 — Conversation entity, lore field, ChatUtterance UI event
├── quickstart.md              # Phase 1 — manual smoke test script
├── contracts/                 # Phase 1 — module-level contracts
│   ├── npc_chat_api.md        #   Public API surface (NPCChat.send/3, find/2)
│   ├── conversation.md        #   Conversation GenServer contract
│   ├── system_prompt.md       #   The chat system prompt
│   ├── tools.md               #   The two LLM tools (say, emote) — schema and validation
│   ├── context.md             #   Per-turn context bundle assembly
│   ├── reply.md               #   Structured-reply parser contract
│   ├── ui_events.md           #   ChatUtterance + chat-system message
│   └── render.md              #   Log-entry rendering (chat_speech, chat_emote, chat_system)
├── checklists/
│   └── requirements.md        # From /speckit.specify
└── tasks.md                   # Phase 2 — generated by /speckit.tasks
```

### Source Code (repository root)

The feature lives entirely within the existing Phoenix/Elixir project. New files are bracketed by `+`; modified files by `M`.

```text
agenticrealms/
├── lib/
│   ├── agenticrealms/
│   │   ├── anthropic.ex                                   #   M  (no change needed — already supports tool use; this is the existing client)
│   │   ├── application.ex                                  M     Add Horde.Registry, Horde.DynamicSupervisor, NPCChat.TaskSupervisor children. Pre-declare new atoms used in event payloads (lore key, if needed) following feature 009's atom-table-existence trick.
│   │   └── world/
│   │       ├── npc_chat.ex                               + Public API: send/3, find/2. The dev-facing entry point.
│   │       ├── npc_chat/
│   │       │   ├── conversation.ex                       + GenServer per (player_id, npc_clone_id) — holds history, fires LLM via async Task, enforces the lockout and idle timeout.
│   │       │   ├── system_prompt.ex                      + The chat system prompt (developer entry point — grep'able).
│   │       │   ├── context.ex                            + Builds the user-message context bundle (room + others + objects + player handle).
│   │       │   ├── tools.ex                              + The two tool definitions: say + emote. Both accept {text} only.
│   │       │   ├── reply.ex                              + Parses the LLM `content` array → {:speech, text} | {:emote, text} | {:error, :malformed}.
│   │       │   ├── registry.ex                           + Horde.Registry wrapper. `via_tuple({player_id, npc_clone_id})` helper.
│   │       │   ├── supervisor.ex                         + Horde.DynamicSupervisor wrapper. `start_conversation/2`.
│   │       │   └── task_supervisor.ex                    + Task.Supervisor wrapper (start under Application). Same pattern as IntentResolverTaskSupervisor.
│   │       ├── npc_blueprint.ex                            M  Add `lore` field to defstruct, command attributes, and apply/execute for blueprint creation. Add `lore` to NPCClonedFromBlueprint payload mapping (full-copy inheritance — same pattern as `behaviors`).
│   │       ├── room.ex                                     M  (no changes — rooms have no lore in this feature)
│   │       ├── seed.ex                                     M  Extend Garrick's blueprint with a `lore` paragraph (FR-015).
│   │       ├── ui_events.ex                                M  Add `ChatUtterance` and `ChatSystemMessage` (or unify into one kind dispatch).
│   │       ├── commands/                                   #   No new commands — chat does NOT dispatch through Commanded.
│   │       │   └── create_npc_blueprint.ex                 M  Add `lore` to defstruct.
│   │       ├── events/                                     #   Two events extended for `lore` plumbing (mirror feature 009's behaviors).
│   │       │   ├── npc_blueprint_created.ex                M  Add `lore` to defstruct.
│   │       │   └── npc_cloned_from_blueprint.ex            M  Add `lore` to defstruct.
│   │       ├── schemas/
│   │       │   ├── npc_blueprint.ex                        M  Add `field :lore, :string, default: ""`.
│   │       │   └── npc_clone.ex                            M  Add `field :lore, :string, default: ""`.
│   │       └── projections/
│   │           └── world_projector.ex                      M  Project `lore` onto Blueprint + Clone insert handlers.
│   ├── agenticrealms_web/
│   │   ├── components/
│   │   │   └── game_components.ex                          M  Add log_entry/1 clauses for :chat_speech, :chat_emote, :chat_system.
│   │   └── live/
│   │       └── game_live.ex                                M  Add `chat` command parsing (CommandParser or new branch). Handle ChatUtterance + ChatSystemMessage in handle_info. Wire IntentResolver tool list to include `chat` if natural-language phrasing is to route here (extends feature 005).
│   └── agenticrealms/world/
│       └── command_parser.ex                               M  Recognize `chat <npc> <rest>` (fast path); fall through to IntentResolver otherwise.
├── priv/
│   └── repo/
│       └── migrations/
│           └── YYYYMMDDHHMMSS_add_lore_columns.exs       + Add `lore TEXT NOT NULL DEFAULT ''` to npc_blueprints and npc_clones.
├── test/
│   ├── agenticrealms/
│   │   └── world/
│   │       └── npc_chat/
│   │           ├── conversation_test.exs                 + GenServer state transitions; idle timeout; lockout; history cap.
│   │           ├── system_prompt_test.exs                + System prompt contains all required constraints (FR-008 a–f).
│   │           ├── tools_test.exs                        + Tool schema shape; required fields.
│   │           ├── reply_test.exs                        + Parses speech/emote/malformed.
│   │           ├── context_test.exs                      + Builds context bundle from room + queries.
│   │           ├── npc_chat_test.exs                     + Public API; cluster-discovery semantics (single-node simulated).
│   │           └── registry_test.exs                     + Horde.Registry lookup; pid resolution by key.
│   └── agenticrealms_web/
│       └── live/
│           └── game_live_chat_test.exs                   + LiveView integration (US1–US5 in sequence; tag :integration; uses Req.Test plug to stub the LLM).
└── config/
    ├── config.exs                                          M  (no required change — Anthropic config already exists)
    └── test.exs                                            M  Configure NPCChat (e.g., idle-timeout override for fast tests, fallback message template).
```

**Structure Decision**: Single Phoenix project, same layout as features 005–009. The NPC chat substrate sits under `lib/agenticrealms/world/npc_chat/` so it cohabits with `behaviors/`, `intent_resolver/`, and the rest of the world-domain code. All cluster machinery (Horde registry + supervisor + task supervisor) is added directly to the existing `AgenticRealms.Application` supervision tree as siblings of the existing children — Horde does not own its own application; we run it under our own supervisor for lifecycle clarity.

## Complexity Tracking

> No constitution violations to justify. The Horde dependency is new but is the established Elixir pattern for the user's stated cluster requirement; the simpler alternative (`:global`) is documented in research.md but rejected on the grounds of name-lock scalability concerns.
