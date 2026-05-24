# Contract: `GameComponents` Log-Entry Render Clauses

Two new `log_entry/1` clauses in `lib/agenticrealms_web/components/game_components.ex`. Both are HEEx renderers that consume a log entry payload from `socket.assigns.log` and emit a `<div class="log-entry ...">` element.

## Clause 1: `:npc_speech`

```elixir
def log_entry(%{entry: %{kind: :npc_speech}} = assigns) do
  ~H"""
  <div class="log-entry speech speech-npc">
    <span class="who">{@entry.actor_name}</span> says, &ldquo;{@entry.text}&rdquo;
  </div>
  """
end
```

**Input shape**: `%{kind: :npc_speech, actor_name: "Garrick the Innkeeper", text: "Welcome to the Stone Atrium."}`

**Rendered HTML**:
```html
<div class="log-entry speech speech-npc">
  <span class="who">Garrick the Innkeeper</span> says, &ldquo;Welcome to the Stone Atrium.&rdquo;
</div>
```

**Visual distinction**:
- Base class `.speech` matches feature 004's player speech — same general styling.
- Modifier class `.speech-npc` available for future per-kind styling (default: no override).
- The actor name (`Garrick the Innkeeper`) is what distinguishes this from player speech at a glance — NPC display names don't match player usernames.

**FR-011 compliance**: the rendered actor name is the bare display name (`Garrick the Innkeeper`), NEVER `Garrick the Innkeeper#1`. No call to `Schemas.NPCClone.debug_id/1` happens in this render path.

## Clause 2: `:room_speech`

```elixir
def log_entry(%{entry: %{kind: :room_speech}} = assigns) do
  ~H"""
  <div class="log-entry narrate narrate-room">
    {@entry.text}
  </div>
  """
end
```

**Input shape**: `%{kind: :room_speech, text: "The cool air carries the scent of rain."}`

**Rendered HTML**:
```html
<div class="log-entry narrate narrate-room">
  The cool air carries the scent of rain.
</div>
```

**Visual distinction**:
- NO actor name. No "X says" framing. No quotation marks. Just the line.
- Base class `.narrate` for italic / ambient styling (consistent with the existing `:narrate` log entry kind if one exists; otherwise defines the look).
- Modifier class `.narrate-room` available for future per-source styling.

## CSS additions

If the existing CSS doesn't already have `.speech` and `.narrate` classes, add minimal styles to `assets/css/app.css` (or wherever GameLive's styles live):

```css
.log-entry.speech { /* feature 004 player speech */ }
.log-entry.speech.speech-npc { /* feature 009 NPC speech — same look by default */ }

.log-entry.narrate { font-style: italic; opacity: 0.85; }
.log-entry.narrate.narrate-room { /* feature 009 room narration — italic ambient default */ }
```

Specific colors / typography are at the project's existing design-language discretion. The contract is structural: NPC speech looks like player speech (actor name + quoted line); room narration looks like ambient text (no actor, italicized).

## Where these clauses fit

The `log_entry/1` function in `GameComponents` is a function-clause-based dispatch table. The two new clauses are added alongside existing clauses for `:speech` (feature 004), `:room` (feature 003), `:system`, `:detail`, `:narrate`, etc. The dispatch order follows pattern-match specificity — the most-specific clauses (with `target_kind` filters) go first.

## Test surface

Covered by the integration test in `test/agenticrealms_web/live/game_live_behaviors_test.exs` which renders a LiveView, triggers behaviors, and asserts the rendered HTML contains the expected `<div class="log-entry speech speech-npc">` and `<div class="log-entry narrate narrate-room">` elements with the expected text and structure.

The integration test ALSO asserts the absence of unwanted patterns:
- No `Garrick the Innkeeper#\d+` substring (FR-011, no debug-id leak).
- No `<span class="who">` for `:room_speech` entries (no-attribution rule).
- No `"says"` substring in `:room_speech` entries (room never speaks "as itself").
