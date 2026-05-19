# Contract — Text-input Parser

**Date**: 2026-05-18
**Branch**: `003-persisted-world`
**Companion docs**: [`../plan.md`](../plan.md), [`commands.md`](commands.md)

The `AgenticRealms.World.CommandParser` module turns the raw text from the player's input box into a structured command (or a sentinel for empty/unknown input). It is the only entry point for translating user text into the world's command vocabulary and owns the entirety of FR-006 (movement aliases), FR-017 (case/whitespace tolerance), FR-018 (unknown commands), and FR-019 (empty input).

The parser does **not** touch the database, the aggregates, or the read models. Its output is purely structural.

---

## Input

A single string from the LiveView form: `String.t()` (may contain any whitespace, any case).

## Output

One of:

```elixir
{:empty}
{:unknown, raw_text :: String.t()}
{:look}
{:inventory}
{:move, direction :: :north|:south|:east|:west|:up|:down}
{:take, name :: String.t()}      # name is downcased + trimmed
{:drop, name :: String.t()}      # name is downcased + trimmed
{:invalid_take_target}            # `take` with no argument
{:invalid_drop_target}            # `drop` with no argument
```

The parser is pure; it never raises.

---

## Verb table

Verbs are matched by lowercasing the first whitespace-delimited token of the trimmed input. Object names (for `take`/`drop`) are the remainder of the input, also lowercased and trimmed.

| First token (lowercased) | Result | FR |
|---|---|---|
| (empty after trim) | `{:empty}` | FR-019 |
| `look`, `l` | `{:look}` (any trailing text after `look` is ignored — `look at lantern` and `look` both produce `{:look}` for this feature, since object-targeted look is out of scope) | FR-005 |
| `inventory`, `inv`, `i` | `{:inventory}` | FR-014 |
| `go` | needs second token; resolve via direction table | FR-006 |
| `north`, `n` | `{:move, :north}` | FR-006 |
| `south`, `s` | `{:move, :south}` | FR-006 |
| `east`, `e` | `{:move, :east}` | FR-006 |
| `west`, `w` | `{:move, :west}` | FR-006 |
| `up`, `u` | `{:move, :up}` | FR-006 |
| `down`, `d` | `{:move, :down}` | FR-006 |
| `take`, `get`, `pick` | second-and-beyond → name; if missing → `{:invalid_take_target}` | FR-009 |
| `drop`, `put` | second-and-beyond → name; if missing → `{:invalid_drop_target}` | FR-012 |
| anything else | `{:unknown, raw_text}` | FR-018 |

**Note on aliases for take/drop**: `get` and `pick` are accepted as `take` aliases (common MUD ergonomics); `put` is accepted as `drop`. These are not separately specified in the spec but are not in conflict with any FR. They can be removed in implementation if the team prefers strict literal vocabulary.

**Note on `go` ambiguity**: `go` alone with no direction → `{:unknown, "go"}`. `go xyz` where `xyz` is not a recognized direction → `{:unknown, "go xyz"}`. This treats `go` strictly as a movement verb; alternative directions never produced silent failures (SC-002 compliance).

**Object name normalization for `take`/`drop`**:

1. Strip the leading verb token and any whitespace after it.
2. Lowercase the remainder.
3. Collapse internal runs of whitespace to single spaces (`take  Brass   Lantern` → `take brass lantern`).
4. The downstream `Queries.resolve_object_in_room/2` and `resolve_object_in_inventory/2` perform the actual name match against `LOWER(world_objects.name)` plus the same normalization.

---

## LiveView dispatch table

`GameLive.handle_event("submit_command", %{"text" => raw}, socket)` calls `CommandParser.parse(raw)` and dispatches per the result:

| Parser result | LiveView action |
|---|---|
| `{:empty}` | Return `{:noreply, socket}` with no log mutation (FR-019). |
| `{:unknown, raw}` | Append `%{kind: :system, text: "I don't understand \"#{raw}\"."}` to the session log (FR-018). |
| `{:look}` | Call `World.Queries.look_room(player_id)`; append `%{kind: :room, room: %RoomView{}}` to log. No command dispatch. |
| `{:inventory}` | Call `World.Queries.list_inventory(player_id)`; format as multi-line system entry (FR-014). |
| `{:move, dir}` | Call `World.Commands.move(player_id, dir)`. On `:ok`: append fresh `%{kind: :room, room: …}` for the destination (FR-008). On `{:error, :no_exit_in_direction}`: append `"You can't go that way."` system entry (FR-007). |
| `{:take, name}` | Call `World.Commands.take(player_id, name)`. Map error atoms to FR-aligned system messages per `commands.md` § "Command → log-entry mapping". |
| `{:drop, name}` | Symmetric to `take`. |
| `{:invalid_take_target}` | Append `"Take what?"` system entry. (Reasonable default; no FR specifies the exact wording.) |
| `{:invalid_drop_target}` | Append `"Drop what?"` system entry. |

The LiveView is the only thing that interprets parser results — the parser itself stays free of UI concerns.

---

## Test matrix

`test/agenticrealms/world/command_parser_test.exs` MUST cover at minimum:

| # | Input | Expected output |
|---|---|---|
| 1 | `""` | `{:empty}` |
| 2 | `"   "` | `{:empty}` |
| 3 | `"\n\t  "` | `{:empty}` |
| 4 | `"look"` | `{:look}` |
| 5 | `"  LOOK  "` | `{:look}` |
| 6 | `"l"` | `{:look}` |
| 7 | `"look around"` | `{:look}` (trailing text ignored) |
| 8 | `"inventory"`, `"inv"`, `"i"`, `"INV"` | `{:inventory}` |
| 9 | `"north"`, `"n"`, `"N"`, `"  north  "` | `{:move, :north}` |
| 10 | `"south"`, `"s"` | `{:move, :south}` |
| 11 | `"east"`, `"e"` | `{:move, :east}` |
| 12 | `"west"`, `"w"` | `{:move, :west}` |
| 13 | `"up"`, `"u"` | `{:move, :up}` |
| 14 | `"down"`, `"d"` | `{:move, :down}` |
| 15 | `"go north"`, `"go  NORTH"` | `{:move, :north}` |
| 16 | `"go"` | `{:unknown, "go"}` |
| 17 | `"go nowhere"` | `{:unknown, "go nowhere"}` |
| 18 | `"take brass lantern"` | `{:take, "brass lantern"}` |
| 19 | `"  TAKE   Brass  Lantern  "` | `{:take, "brass lantern"}` |
| 20 | `"take"` | `{:invalid_take_target}` |
| 21 | `"get journal"` | `{:take, "journal"}` |
| 22 | `"pick up journal"` | `{:take, "up journal"}` (we treat `pick` as an alias for `take`; `up` becomes part of the name. If implementation prefers `pick up` as a two-word alias, this test changes to `{:take, "journal"}`. Default decision: keep `pick` as a one-word alias for simplicity, accept the awkward `pick up`.) |
| 23 | `"drop letter"` | `{:drop, "letter"}` |
| 24 | `"drop"` | `{:invalid_drop_target}` |
| 25 | `"put letter"` | `{:drop, "letter"}` |
| 26 | `"dance"` | `{:unknown, "dance"}` |
| 27 | `"hello world"` | `{:unknown, "hello world"}` |
| 28 | `"   look at letter   "` (extraneous "look at letter" form — out of scope) | `{:look}` (look ignores everything after the verb) |
| 29 | Mixed case names: `"take Brass Lantern"` | `{:take, "brass lantern"}` |
| 30 | `"take  "` (verb + only whitespace) | `{:invalid_take_target}` |

The parser's job ends here. The downstream `World.Commands.take/3` and friends handle `:no_such_object`, `:ambiguous`, `:object_is_fixed`, etc., as documented in `commands.md`.
