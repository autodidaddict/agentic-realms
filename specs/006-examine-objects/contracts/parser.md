# Contract: `CommandParser` — `look` extension

Extension to the existing parser in `lib/agenticrealms/world/command_parser.ex`. The `look` arm changes from a degenerate `{:look}`-only match to a target-aware shape.

## Sentinels

```elixir
# Existing (unchanged on the no-target path):
{:look}

# NEW:
{:look, target :: String.t()}
```

`target` is always non-empty, lowercased, and whitespace-collapsed when it reaches the LiveView (or the literal `"__self__"` sentinel for `me` / `self`). The parser is responsible for normalization; downstream handlers do not re-normalize.

## Rules

- `look` (no rest) → `{:look}`
- `l` (no rest) → `{:look}`
- `look me` → `{:look, "__self__"}`
- `look self` → `{:look, "__self__"}`
- `l me` → `{:look, "__self__"}`
- `l self` → `{:look, "__self__"}`
- `look <anything else>` → `{:look, normalize(<anything else lowercased>)}`
- `look   the   brass   lantern   ` → `{:look, "the brass lantern"}` (trim + collapse whitespace + lowercase)
- `LOOK Alice` → `{:look, "alice"}` (verb is already case-insensitive; argument is lowercased)
- `look 'hello` → `{:look, "'hello"}` — apostrophe is not a meta-character once the verb has been recognized; this would be a valid (but meaningless) target name.

The `me` / `self` aliasing is scoped to the `look` arm only. `take me`, `drop self`, etc. are NOT affected (those still use literal lowercased target names — there is no inherent meaning to self-take or self-drop, and downstream `Queries.resolve_object_in_*` will return `:no_such_object` for those).

## Why preserve the existing `{:look}` sentinel

`{:look}` (no target) is the parser-distinct signal that the LiveView should render the existing room view — same behavior, same path, same handler. Splitting into two sentinels (instead of `{:look, ""}` / `{:look, nil}`) keeps the handler-side `case` pattern-matching obvious and pre-empts the SC-003 latency concern: no-target `look` does not touch the new `Examine` module at all; it remains a single `Queries.look_room/1` call.

## Verb aliases

The `look` verb is unchanged: the canonical form is `look`, with `l` as the existing single-letter alias. No new aliases are added (the natural-language phrasings — `examine`, `inspect`, etc. — are handled by the LLM resolver, not the fast parser).

## Test surface

`test/agenticrealms/world/command_parser_test.exs` gains a new context block covering:

- `look` / `l` → `{:look}` (existing, retained).
- `look brass lantern` → `{:look, "brass lantern"}`.
- `look BRASS LANTERN` → `{:look, "brass lantern"}` (lowercased).
- `look   the   journal  ` → `{:look, "the journal"}` (trim + collapse).
- `look me` → `{:look, "__self__"}`.
- `look self` → `{:look, "__self__"}`.
- `look ME` → `{:look, "__self__"}` (case-insensitive alias).
- `l self` → `{:look, "__self__"}` (single-letter verb + alias).
- `look someone` → `{:look, "someone"}` (NOT mapped to `__self__` — only the two literal aliases).
- `look mead` → `{:look, "mead"}` (NOT mapped — prefix `me` does not trigger the alias because the full lowercased argument is `mead`, not `me`).
