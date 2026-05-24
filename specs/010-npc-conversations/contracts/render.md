# Contract: Log-entry rendering for chat (game_components.ex)

New `log_entry/1` clauses for the chat-private surface. Same component-function pattern as feature 009.

## New `log_entry` clauses

### `:chat_system` (the meta-frame messages)

```heex
<div class={"log-entry chat-system " <> kind_class(@entry.kind)}>
  {@entry.text}
</div>
```

Where `kind_class(:chat_new)` → `"chat-new"`, etc. — distinct CSS classes so designers can style each variant.

### `:chat_speech`

```heex
<div class="log-entry speech speech-npc speech-chat">
  <span class="who">{@entry.actor_name}</span> says,
  &ldquo;{@entry.text}&rdquo;
</div>
```

Visually matches feature 009's `:npc_speech` (same `speech-npc` class) but adds a `speech-chat` class so private-chat speech can be styled distinctly from public NPC speech if desired.

### `:chat_emote`

```heex
<div class="log-entry emote emote-chat">
  <span class="who">{@entry.actor_name}</span>
  {@entry.text}
</div>
```

Mirrors feature 004's existing `:emote` rendering but on the private chat surface.

## GameLive log-entry map shape

When GameLive receives a `ChatUtterance` or `ChatSystemMessage` via `handle_info/2`, it appends a map to `@log` of the form:

```elixir
# From ChatUtterance{kind: :chat_speech, ...}
%{kind: :chat_speech, actor_name: "Garrick the Innkeeper", text: "Hello, friend."}

# From ChatUtterance{kind: :chat_emote, ...}
%{kind: :chat_emote, actor_name: "Garrick the Innkeeper", text: "raises an eyebrow curiously"}

# From ChatSystemMessage{kind: :chat_new, ...}
%{kind: :chat_system, kind_variant: :chat_new, text: "You begin a conversation with Garrick the Innkeeper."}

# From ChatSystemMessage{kind: :chat_fallback, ...}
%{kind: :chat_system, kind_variant: :chat_fallback, text: "Garrick the Innkeeper seems lost in thought."}
```

(The `:chat_system` clause discriminates on `kind_variant` for CSS class assignment; the text is rendered as-is.)

## Ordering invariant

For any single chat command that succeeds:

1. `ChatSystemMessage{kind: :chat_new | :chat_continuing}` MUST render BEFORE the `ChatUtterance` reply (FR-003).
2. The Conversation GenServer broadcasts the system message synchronously inside the `{:send, ...}` `handle_call/3` BEFORE returning. The reply broadcast happens later, when `{:llm_result, ...}` arrives.
3. Because PubSub preserves per-sender ordering and the system message is broadcast before the reply broadcast (on the same Conversation pid), the GameLive's `handle_info/2` receives them in order — so the rendered log preserves the order.

## Test surface

- `GameComponentsTest` (rendering unit tests):
  - `:chat_speech` renders the NPC name in a `<span class="who">` and the text in curly quotes.
  - `:chat_emote` renders the NPC name followed by the text, no quotes.
  - `:chat_system` renders the text with a discriminating CSS class per variant.

- LiveView integration:
  - The new-conversation indicator string appears in the chatting player's rendered HTML.
  - After a successful chat, both the indicator AND the reply appear in the log, with the indicator first.
  - FR-008d audit: across all rendered chat replies in the test suite, the substring `"as an AI"` (and the other meta-reference triggers from SC-002) is absent. The test uses stubbed canned replies that intentionally do NOT contain these substrings; the assertion is verifying the rendering pipeline doesn't synthesize them.
