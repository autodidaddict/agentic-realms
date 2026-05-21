# Contract: System Prompt — `priv/intent_resolver/system_prompt.md`

The system prompt receives three precise edits. The cache marker on the system block (see `lib/agenticrealms/world/intent_resolver.ex:90-99`) means any change here invalidates the cache for one deploy; the changes below are the minimum the feature requires.

## Edit 1 — `look` tool guidance paragraph

**Remove** (from the "Game rules and tool-use protocol" section):

> DO NOT substitute a near-mapping action. If the player asks to `examine`, `inspect`, `study`, or `read` a specific object but no such action exists, call `refuse` — do NOT call `look` as a stand-in. The `look` tool shows the current room as a WHOLE, never a specific object.

**Replace with**:

> For object or player examination — `examine`, `inspect`, `study`, `read`, `look at <X>`, `take a closer look at <X>`, `check out the <X>`, `what does the <X> look like` — call the `look` tool with the `target` argument set to the player's wording for the object or player. The game does its own case-insensitive resolution against actual room contents, inventory, and other players present.
>
> Call `look` with no `target` argument ONLY when the player wants to see the WHOLE room (their surroundings as a whole — name, exits, every object visible, every other player present). `look at the room`, `survey the area`, `where am I` → `look` with no `target`.

## Edit 2 — Example 3

**Remove the current example 3** (near-mapping refusal):

> ## Example 3 — near-mapping refusal (DO NOT substitute look)
>
> ```
> Current room: Stone Atrium
> Objects here: brass lantern
> Player typed: examine the lantern closely
> ```
>
> → call `refuse` with `message` = "You can `look` to see the whole room, but examining specific objects isn't supported yet."

**Replace with**:

> ## Example 3 — examining a specific object
>
> ```
> Current room: Stone Atrium
> Objects here: brass lantern
> Player typed: examine the lantern closely
> ```
>
> → call `look` with `target` = "brass lantern"

## Edit 3 — Append new examples 10–13

After existing example 9, append:

> ## Example 10 — examining an inventory object
>
> ```
> Your inventory: leather-bound journal
> Player typed: read the journal
> ```
>
> → call `look` with `target` = "leather-bound journal"
>
> ## Example 11 — examining another player
>
> ```
> Other players present: alice
> Player typed: take a closer look at alice
> ```
>
> → call `look` with `target` = "alice"
>
> ## Example 12 — self-examination
>
> ```
> Player typed: look at myself
> ```
>
> → call `look` with `target` = "me"
>
> ## Example 13 — whole-room look (sanity check, NOT a refusal)
>
> ```
> Player typed: take in my surroundings
> ```
>
> → call `look` (no arguments)

## Edit 4 — Final reminders

**Remove** the existing bullet:

> Near-mapping intent (examine / inspect / study / read a specific object) → `refuse` with a hint. Never substitute `look`.

**Replace with**:

> Examine / inspect / study / read / look-at intent → `look` with a `target`. Whole-room `look` only when the player wants to see EVERYTHING, not a specific thing. Per-target detail and whole-room view are now both `look` — the `target` argument is the discriminator.

## Caching note

These four edits collectively change the prompt body — the ephemeral cache prefix is invalidated. The first post-deploy request pays an uncached invocation (~500–1500ms extra at Haiku rates), then subsequent requests warm the cache normally. No client-side migration needed. Same one-deploy-cost pattern feature 005 documented for its initial system-prompt ship.

## Few-shot example count

Before this feature: 9 examples. After: 13 examples (existing 1–2, REWRITTEN example 3, existing 4–9, NEW examples 10–13). The total prompt size grows by ~30 lines of markdown — still well under Haiku's 4096-token minimum cacheable prefix threshold, so the cache marker remains a no-op at current size (just as it was in 005). Kept for future-proofing.
