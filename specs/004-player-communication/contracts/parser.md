# Contract — `AgenticRealms.World.CommandParser` additions

This contract defines the additions to `command_parser.ex` for feature 004. Existing 003 sentinels (`{:look}`, `{:inventory}`, `{:move, dir}`, `{:take, name}`, `{:drop, name}`, `{:invalid_take_target}`, `{:invalid_drop_target}`, `{:empty}`, `{:unknown, raw}`) are unchanged.

## New result type extensions

```elixir
@type result ::
        # … existing 003 variants unchanged …
        | {:say, text :: String.t()}
        | {:say_empty}
        | {:emote, text :: String.t()}
        | {:emote_empty}
        | {:tell, recipient :: String.t(), text :: String.t()}
        | {:tell_no_recipient}
        | {:tell_no_text, recipient :: String.t()}
        | {:whisper, recipient :: String.t(), text :: String.t()}
        | {:whisper_no_recipient}
        | {:whisper_no_text, recipient :: String.t()}
```

The verb-specific `_empty` / `_no_recipient` / `_no_text` sentinels exist so the LiveView (or the facade) can produce verb-tailored refusal copy (e.g., "Say what?" vs "Emote what?" vs "Tell whom what?") without inspecting the original raw string a second time.

## Grammar (informal)

Input is the raw text submitted via the chat input. Whitespace handling: leading/trailing whitespace is trimmed, and runs of internal whitespace **within** the `<text>` argument are preserved verbatim (do not collapse — players may legitimately type multiple spaces in roleplay).

### `say`

| Input pattern (case-insensitive on the verb) | Sentinel |
|----------------------------------------------|----------|
| `say <text>` where text trims to non-empty | `{:say, text}` (text trimmed, original case preserved) |
| `say` alone, or `say   ` (whitespace only after verb) | `{:say_empty}` |
| `'<text>` where text trims to non-empty (no space required after the apostrophe; one space is consumed if present) | `{:say, text}` |
| `'` alone, or `'   ` | `{:say_empty}` |

### `emote`

| Input pattern | Sentinel |
|---------------|----------|
| `emote <text>`, `me <text>`, `:<text>` where text trims to non-empty | `{:emote, text}` |
| any of the three with empty/whitespace-only text | `{:emote_empty}` |

For the `:` shortcut, the single colon prefix is consumed without requiring a space, mirroring `'` for say. `:waves` → `{:emote, "waves"}`. `:` alone → `{:emote_empty}`.

The `me` and `emote` verb forms require either nothing or whitespace after them (so a word starting with `me` like `mention` does not get mis-parsed as `me ntion`).

### `tell`

| Input pattern | Sentinel |
|---------------|----------|
| `tell <recipient> <text>`, `t <recipient> <text>` | `{:tell, recipient, text}` |
| `tell` alone, `t` alone | `{:tell_no_recipient}` |
| `tell <recipient>` (no further text), `t <recipient>` | `{:tell_no_text, recipient}` |

`<recipient>` is parsed as **a single whitespace-delimited token**. Username validation in `Accounts.Player` already constrains usernames to `[a-zA-Z0-9_-]+` of length 3..30, so no token can legitimately contain a space.

Whitespace handling for `tell`:

- All trailing whitespace after the verb is consumed before splitting out the recipient.
- Whitespace between recipient and text is consumed (any amount).
- Whitespace within the text body is preserved.

### `whisper`

Identical grammar to `tell`, with `whisper` as the only verb form. The originally-planned `w` alias was dropped during implementation because feature 003 already uses `w` as the `west` movement shortcut.

| Input pattern | Sentinel |
|---------------|----------|
| `whisper <recipient> <text>` | `{:whisper, recipient, text}` |
| `whisper` alone | `{:whisper_no_recipient}` |
| `whisper <recipient>` (no further text) | `{:whisper_no_text, recipient}` |

### Mutual exclusion

`tell` and `t` MUST NOT be accepted as whisper aliases, and `whisper` and `w` MUST NOT be accepted as tell aliases. (FR-004.)

## Case preservation contract

For all four new verbs the **verb itself** is matched case-insensitively (`SAY hello`, `Tell Alice hi`, `Whisper carol shh`, `:Waves`, `'HELLO` all parse). The **`<text>` argument** is returned with its **original casing** intact. The **`<recipient>` token** is returned with its **original casing** intact (the facade is responsible for case-insensitive resolution downstream).

The existing 003 verbs continue to receive their argument in lowercase (existing behavior). This is achieved by checking for new-verb prefixes against a downcased copy of the first word, but slicing the rest of the *original trimmed input* (not the downcased copy) for the new-verb sentinels' payloads. Existing verbs use the downcased rest as today.

## Conflict resolution order

When multiple verb patterns could match, the parser MUST check in this order (first match wins):

1. Apostrophe-prefix shortcut (`'…` → say)
2. Colon-prefix shortcut (`:…` → emote)
3. Verb-word matching (case-insensitive first word):
   - `say`
   - `emote` / `me`
   - `tell` / `t`
   - `whisper` / `w`
   - then existing 003 verbs (`look`, `l`, `inventory`/`inv`/`i`, `take`/`get`/`pick`, `drop`/`put`, direction shortcuts)

In particular: `t` MUST match `tell` (not `take`, even though both start with `t`). The conflict is resolved by literal equality on the whole first word — `t` matches only `t`, not `take`. (Existing 003 has `take` but no `t` alias.)

## Empty input

If the trimmed input is the empty string, the parser returns `{:empty}` (unchanged from 003). The empty-after-verb refusal sentinels (`{:say_empty}` etc.) only fire when the verb itself was present.

## Unknown input

If no rule matches, the parser falls through to the existing `{:unknown, raw}` path. (The original trimmed string, NOT the downcased copy, is returned in `raw`.)
