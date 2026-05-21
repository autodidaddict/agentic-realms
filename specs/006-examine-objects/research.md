# Phase 0 Research: Examine Objects and Players

This feature has no NEEDS CLARIFICATION markers in the spec, no new external dependencies, and no novel architectural patterns — it composes existing infrastructure. The research below documents the load-bearing technical decisions that the plan rests on.

## R1 — Where to put the target-resolution policy

**Decision**: A new module `AgenticRealms.World.Examine` (with a thin nested `Examine.Match` struct).

**Rationale**:
- `World.Queries` is a flat module of raw, single-purpose reads (`current_room_of/1`, `look_room/1`, `resolve_object_in_room/2`, etc.). Each function is one indexed DB read with no policy. Adding the FR-006a precedence tree (exact > partial, inventory > room, mixed-kind tie → refuse, partial-tie → refuse) would dilute that posture and force the disambiguation logic to live next to unrelated functions like `object_fixed?/1`.
- `World.Communication.RecipientResolver` is the precedent for "isolated policy-laden lookup": it's a separate module dedicated to one resolution job (player name → `{:ok, %{id, username}}`), with its own test file. Examine's target resolution is a strict superset of that pattern (three scopes vs. one, three-stage precedence vs. two).
- Putting it in its own module gives the `examine_test.exs` test file a single subject and lets the LiveView integration test mock or stub it cleanly when needed.

**Alternatives considered**:
- *Inline in `Queries`* — rejected for the reasons above.
- *Inline in `GameLive`* — rejected. The handler should stay UI-shaped (read, render, error-log); pulling the resolution policy into the LiveView mixes concerns and breaks the "the LiveView orchestrates, the World decides" invariant established in 003/004/005.
- *Inside `IntentResolver`* — rejected. The resolver's job is natural-language → action mapping. Target resolution happens AFTER an action is chosen, against actual world state, and is also exercised by the fast path (where the LLM is uninvolved).

## R2 — Target-resolution precedence algorithm

**Decision**: Single function `Examine.resolve_target/2` implementing this three-stage tree:

```
Stage 1 — collect EXACT case-insensitive matches across all three scopes:
  - room objects (Queries.look_room/1 → .objects)
  - inventory objects (Queries.list_inventory/1)
  - same-room players (Queries.other_occupants_of/2 + the acting player themselves)

  Count exact matches by kind:
    - 0 exact total → fall to Stage 3 (partial matching)
    - 1 exact total → that target wins (Stage 1 returns it)
    - >1 exact, all are objects → Stage 2
    - >1 exact, all are players → refuse (:ambiguous_player) — pathological but
      possible across case variants; we already refuse to guess in Communication
    - >1 exact, mixed object + player → refuse (:ambiguous_mixed_kind) per FR-006a's
      "they are not the same kind of target" rule

Stage 2 — inventory > room tiebreak (only for multi-exact object case):
  - exactly one match is in the player's inventory → inventory copy wins
  - zero matches in inventory (all in room) → refuse (:ambiguous_in_room)
  - multiple matches in inventory → refuse (:ambiguous_in_inventory)

Stage 3 — partial / substring matching (only when 0 exact matches existed):
  - same three scopes; substring match on lowercased names
  - 0 matches → :no_such_target
  - 1 match → it wins
  - >1 match → refuse (:ambiguous_partial)
```

**Rationale**:
- Mirrors the spec's FR-006a ordering literally — easy to test stage-by-stage.
- The "exact > partial" priority matches what take/drop already do via `Queries.resolve_object_in_room/2` (which uses `normalize_name/1` and equality — exact-only). Examine adds partial as a fallback because the spec's edge cases call for it (`look lantern` should work even if the name is "brass lantern"), while take/drop's stricter behavior is unchanged.
- Stage 1's "across all three scopes" is the critical step: it ensures that an exact-match player and an exact-match object don't silently resolve to one of them — they refuse, matching FR-006a's "never tie with object names" rule.
- Player ambiguity (`>1 exact players`) is pathological because usernames have a uniqueness constraint at the Accounts level, but a case-variant collision is theoretically possible (`Alice` vs. `alice`). The Communication recipient resolver handles this with `:ambiguous` already; we mirror it.

**Alternatives considered**:
- *Weight-based scoring* (e.g., assign points: exact = 100, inventory = +10, room = +5, partial = 50, pick the highest) — rejected. The spec's "refuse rather than guess" guidance makes scoring inappropriate; refusals must be reachable by construction, not by tiebreakers that always have a winner.
- *Levenshtein / fuzzy matching for partial stage* — rejected. The spec explicitly defers to existing take/drop matching conventions, which are case-insensitive equality + naive substring. Fuzzy matching is a candidate future feature, not a 006 concern.

## R3 — `look` tool schema change in the LLM resolver

**Decision**: Add an OPTIONAL `target` string property to the existing `look` tool's `input_schema`. Keep the property list non-required so the model can still call `look` with no arguments for the room view.

```json
{
  "type": "object",
  "properties": {
    "target": {
      "type": "string",
      "description": "Optional. The name of a specific object or player to examine. Omit this to show the whole room. When the player wants to examine, inspect, study, or read a specific thing, pass its name here (case-insensitive)."
    }
  },
  "required": []
}
```

**Rationale**:
- One tool, two modes — matches the player's mental model ("look at things"). Spec FR-001 frames this as one verb with an optional target, not two distinct actions.
- Keeping `target` optional preserves the existing no-target invocation contract; `IntentResolver.to_action("look", _)` already accepts any input map, so adding a clause that matches on `%{"target" => t}` extends it cleanly.
- Anthropic's tool schema validation accepts properties that aren't in `required`. The model will infer from the description when to include the property.

**Alternatives considered**:
- *New `examine` tool* — rejected. Spec FR-001 is explicit that this extends `look`. Two tools would double the prompt surface, and the player-facing UX (the `:detail` log entry) is the same for both, so a separation buys nothing.
- *Make `target` required and add a new no-target tool* — rejected. Same reason; the canonical no-target `look` is the most common invocation in playtest data and shouldn't be deprecated.

## R4 — System prompt and few-shot examples diff

**Decision**: Three targeted edits to `priv/intent_resolver/system_prompt.md`:

1. **Tool-purpose paragraph** (currently the bullet `DO NOT substitute a near-mapping action. If the player asks to examine, inspect, study, or read a specific object but no such action exists, call refuse...`): REWRITE to:
   ```
   For object or player examination (`examine`, `inspect`, `study`, `read`,
   `look at <X>`, `take a closer look at <X>`): call `look` with the `target`
   argument set to the object or player's name. Do NOT use `refuse` for these —
   the game now supports per-target examination.
   ```

2. **Example 3** ("near-mapping refusal"): REWRITE from a refusal demo to a successful look-with-target demo:
   ```
   Current room: Stone Atrium
   Objects here: brass lantern
   Player typed: examine the lantern closely
   ```
   → call `look` with `target` = "brass lantern"

3. **Add Examples 10–12** covering:
   - Examining an inventory object: `Your inventory: leather-bound journal / Player typed: read the journal` → `look` with `target` = "leather-bound journal".
   - Examining another player: `Other players present: alice / Player typed: who is alice?` → `look` with `target` = "alice".
   - Examining self: `Player typed: look at myself` → `look` with `target` = "<acting player's username>" — but since the prompt doesn't currently include the acting player's name in context, we instead instruct the model to pass the literal `me` and let the Examine module's `me`/`self` alias logic resolve it at the world layer.

**Rationale**:
- The current prompt actively works AGAINST this feature (example 3 demonstrates the wrong behavior post-006). The rewrite is mandatory, not optional.
- New examples 10–12 cover the three target categories the model needs to learn (room object, inventory object, player) plus the self case, which requires the most explicit guidance.
- Pushing `me`/`self` resolution to the world layer (the parser maps them; Examine resolves them) keeps the system prompt simple — the model just preserves the player's wording.

**Alternatives considered**:
- *Inject the acting player's username into the per-request context snapshot* — viable but more invasive. The current `ContextSnapshot.render/3` doesn't include the player's own name (it's implicit). Adding it just for the self-examination case is a wider blast radius than the one-line `me`/`self` alias in the parser.

## R5 — New `:detail` log-entry kind vs. reusing existing kinds

**Decision**: New `:detail` kind with two render branches based on a `target_kind` field (`:object | :player`).

**Rationale**:
- FR-003 mandates a visual / structural distinction from `:room`. The existing `:system` kind (one-line plain text) is too plain for object examinations, which can have multi-line long descriptions. The existing `:room` kind has exits + entities sections that don't apply.
- Two render branches (object vs. player) on the same kind avoids two near-identical clauses in `game_components.ex` (`kind: :detail_object`, `kind: :detail_player`) while still permitting per-branch markup. The render function reads `target_kind` and chooses.
- The shape:
  - `%{kind: :detail, target_kind: :object, name: String.t(), long_description: String.t()}`
  - `%{kind: :detail, target_kind: :player, name: String.t()}` (no long_description field — the placeholder is hard-coded in the render branch, awaiting later feature enrichment).

**Alternatives considered**:
- *Reuse `:system`* — rejected per FR-003.
- *Reuse `:room` with a `target` discriminator* — rejected. The `:room` entry's shape is rigid (exits, objects, other_players) and overloading it would force render-branch logic that's ugly to test.
- *Separate `:detail_object` / `:detail_player` kinds* — viable, but adds two `log_entry/1` clauses that share most of their structure (`<div class="log-entry detail">…</div>`). The `target_kind` dispatch within one clause is cleaner.

## R6 — Fast-path → LLM fallback for unresolved `look` targets

**Decision**: Mirror the FR-001a pattern from feature 005a — `handle_look_target/4` carries an `allow_fallback?` parameter that is `true` on the fast-path entry and `false` from `dispatch_resolved_action/3`. On a `{:error, :no_such_target}` result with `allow_fallback?` true, route the raw input to `handle_unknown/2` (which spawns the resolver task).

**Rationale**:
- This is exactly the same shape as `handle_take` / `handle_drop` — same parameter name, same routing decision tree. Consistency reduces cognitive load and makes the test pattern reusable.
- FR-013 (no fallback loop) is satisfied by passing `allow_fallback? = false` on every LLM-dispatched retry; a `{:error, :no_such_target}` from the second try collapses to a refusal directly.
- Ambiguity refusals (`:ambiguous_*`) MUST NOT trigger the LLM fallback even on the first attempt. They are not "name didn't resolve" — they are "name resolved to too many things." The fallback exists for loose phrasing (`look the lantern with the dent`); routing an ambiguity to the LLM would just produce the same ambiguity (or worse, a confident guess). The handler distinguishes between `:no_such_target` (fallback eligible) and any `:ambiguous_*` (refuse immediately).

**Alternatives considered**:
- *Always refuse on first attempt, no fallback* — rejected. This would regress one of feature 005a's improvements; `look the lantern with the dent` should work for the same reason `take the lantern with the dent` does today.
- *Always fall back, even on LLM-dispatched retries* — rejected. Creates the loop FR-013 explicitly prohibits.

## R7 — `me` and `self` aliasing

**Decision**: Add a parser-level alias step inside the `look <target>` arm only. The parser maps `me` and `self` to the literal sentinel `{:look, "__self__"}` (a reserved string), and the `Examine` module recognizes `"__self__"` as "the acting player" without doing a DB username lookup.

**Rationale**:
- Keeps `me` / `self` from leaking into other commands (`take me`, `drop self`, `tell me` — none of those should be affected).
- The reserved-string sentinel keeps the parser's `{:look, target}` shape uniform — no parser branch returns a special atom or struct. Examine's resolver checks for the sentinel before any DB lookup.
- Spec FR-005a (self-examination) and the edge case "look <self-name>" both work: `look <self-name>` goes through normal player-name resolution against the acting player's username (which is in the visible scope since the player can examine themselves); `look me` / `look self` short-circuit via the sentinel.

**Alternatives considered**:
- *Resolve `me`/`self` at the parser by injecting the player's id* — rejected. The parser is `Player.id`-unaware (it takes a string, returns a sentinel). Wiring player context into it just for this case is over-engineering.
- *Make Examine accept a `:self` atom directly* — rejected. Same reason — the parser's output shape would become heterogeneous (`{:look, String.t()}` vs. `{:look, :self}`), increasing handler complexity for marginal benefit.

## R8 — Telemetry and observability

**Decision**: Add a single `:telemetry` event `[:agenticrealms, :examine, :resolve]` with measurements `%{}` and metadata `%{player_id, target_kind | nil, outcome}` where outcome is `:object | :player | :no_such_target | :ambiguous_*`. No new log lines.

**Rationale**:
- Cheap parity with the IntentResolver's existing telemetry pattern.
- FR-016 (cost-aware logging) already covers the LLM-fallback case via the IntentResolver's per-invocation log line; the fast-path examine doesn't need that level of detail.

**Alternatives considered**:
- *No telemetry at all* — viable; the feature is cheap and observable through the LiveView integration tests. Adding the event costs ~3 lines and unlocks future dashboards.
- *Logger.info per examine* — rejected. The fast path is high-frequency (players will examine objects often); a per-call log line is noisy and provides no diagnostic value the structured telemetry doesn't.
