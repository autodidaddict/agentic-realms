# Quickstart: NPC Conversations (Feature 010)

A small manual smoke test exercising US1–US5 from a fresh login. Assumes the feature is implemented, migrations are run, and the seed has been applied (Garrick has lore).

## Prerequisites

- Postgres running locally.
- `mix ecto.reset` (drops + recreates + migrates + seeds) executed at least once.
- `ANTHROPIC_API_KEY` set in your environment, OR the test mode that uses `Req.Test` stubs (for offline demo).
- The server running: `mix phx.server`.

## Steps

1. **Login as Alice.**
   Open `http://localhost:4000` and register a fresh user `alice_smoke` / `password_password`. After login you should land in the Stone Atrium with Garrick the Innkeeper.

2. **(US1) Start a chat — verify in-character reply and "new conversation" indicator.**

   In the command box, type:

   ```
   chat Garrick where are you from?
   ```

   Expected log entries (in order):

   - `You begin a conversation with Garrick the Innkeeper.` — the `:chat_new` system message.
   - Either `Garrick the Innkeeper says, "..."` (with a reply referencing his bridge-guard / Riverford past from the lore) OR `Garrick the Innkeeper <gestures or expression>.` if he chooses an emote.
   - The reply MUST be in-character. No "as an AI" references.

3. **(US2 + US3) Continue the chat — verify multi-turn coherence AND environmental grounding.**

   Within 60 seconds of step 2, type:

   ```
   chat Garrick who else is here?
   ```

   Expected:

   - `You continue your conversation with Garrick the Innkeeper.` — the `:chat_continuing` system message.
   - A reply that demonstrates awareness of the current room (and any other player who has joined; if you're alone, the NPC acknowledges that).

4. **(US3 — fresh players appear) Open a second browser and login as Bob.**

   In a second incognito window, register `bob_smoke` / `password_password`. He should appear in the Stone Atrium.

   Back in Alice's window, within the 60-second window from step 3, ask:

   ```
   chat Garrick who else is in the room with me?
   ```

   Expected:

   - Continuing indicator.
   - Reply mentions Bob (or acknowledges another player is present).

   **In Bob's window**: he should see NONE of Alice's prompts or Garrick's replies in his log. This is the FR-017 privacy guarantee in action.

5. **(US4 — out-of-lore refusal) Ask Garrick something nonsensical.**

   ```
   chat Garrick what's the weather like on Mars?
   ```

   Expected:

   - Continuing indicator (still inside the 60s window).
   - An in-theme refusal — either a brief verbal redirect ("Mars? Never heard of the place. Where might that be?") or, preferably per the system prompt, an emote (`Garrick the Innkeeper raises an eyebrow curiously.`).
   - NEVER a meta-reference ("as an AI", "I don't have that information", etc.).

6. **(US5 — empty-lore NPC) — optional**

   If you have access to seed editing, temporarily add an NPC with empty lore (no `lore` field set) and chat with them. Expected: short, in-scene replies; refusal-by-emote when asked about backstory.

7. **(Verify history reset) Wait 90 seconds without chatting Garrick.**

   Then type:

   ```
   chat Garrick remember me?
   ```

   Expected:

   - `You begin a conversation with Garrick the Innkeeper.` — the `:chat_new` system message (NOT `:chat_continuing`), because the prior conversation has idled out (FR-006).
   - Garrick's reply has NO recollection of the prior turns from steps 2–5.

8. **(Verify in-flight lockout — FR-020) Spam chat commands.**

   Rapidly type two `chat Garrick ...` messages in succession (the LLM call takes ~1–3s, so submit both within that window).

   Expected:

   - The first command produces the indicator + (eventually) a reply.
   - The second command produces `Garrick the Innkeeper hasn't finished thinking yet — give them a moment.` rather than a second LLM call.
   - After the first reply lands, the next chat command is accepted.

9. **(Move out of the room) From Alice's window:**

   ```
   go north
   ```

   Then:

   ```
   chat Garrick are you there?
   ```

   Expected: a "no such NPC here" rejection (FR-016). No LLM call is made.

10. **(Verify privacy at the wire level — optional)**

    Open the browser devtools, Network tab → WS frame log. While Alice chats with Garrick, observe Bob's WebSocket frames. None of Alice's prompts or Garrick's replies should appear in Bob's stream. This is the FR-017 / SC-007 guarantee at the wire level.

## Pass criteria

- All 9 main steps produce the expected log entries.
- No raw error strings or meta-references appear in any rendered reply.
- Bob's log remains clean throughout Alice's chats with Garrick.
- The 60-second idle behavior produces a fresh-conversation indicator.

## Troubleshooting

- **All chats fall back to "seems lost in thought"**: Check `ANTHROPIC_API_KEY` is exported. The Anthropic client returns `{:error, :no_api_key}` when missing, which triggers the FR-011 fallback path.
- **No NPC found**: Verify the seed has run (`mix ecto.reset`) and Garrick is in the Stone Atrium. If you spawn into a different room, navigate to a room with an NPC.
- **History never resets**: Confirm the idle-timeout configuration is at default 60_000 ms in `config/config.exs` (or wherever overridden).
