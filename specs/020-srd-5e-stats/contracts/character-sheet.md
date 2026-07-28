# Contract: The Character Sheet UI

**Feature**: 020-srd-5e-stats (FR-015 through FR-024, FR-032, FR-033)

## Tabs

Three tabs in a strip inside the existing `<.modal title="Character Sheet">`. The modal chrome, its glyph, its close control, and its Escape handling are untouched.

| Tab | Key | Contents |
|---|---|---|
| Main | `:main` | identity, vitals, derived combat values |
| Abilities | `:abilities` | six scores, six saves, eighteen skills |
| Spells | `:spells` | placeholder only |

`:main` is selected whenever the sheet opens (FR-020). Because the modal is unmounted on close and the assign is reset when `open_modal` fires for `"stats"`, this is the natural behavior rather than something to enforce separately.

### Tab switching is client-side (FR-019, Principle III)

All three panels render into the DOM at once; the tab strip toggles which is visible using `Phoenix.LiveView.JS` (`JS.hide/JS.show` plus an `aria-selected` swap), with no `phx-click` reaching the server.

This satisfies Principle III without qualification: which tab is showing is not authoritative state, not persisted, and not broadcast, so a round-trip would buy nothing. The whole sheet is already in the socket assigns, so rendering all three costs one extra render of about forty rows.

Rejected: `phx-click="select_tab"` with a `:sheet_tab` assign. Simpler to write, but it is a server round-trip for a purely local concern, which the principle asks us not to do.

### Accessibility and layout

`role="tablist"` on the strip, `role="tab"` with `aria-selected` on each button, `role="tabpanel"` on each panel. The existing `.mode-switch` in `layouts.ex` already uses `role="tablist"`, so this follows a pattern the project has.

The strip must stay usable at narrow widths (edge case in the spec): it wraps rather than scrolls, and no tab is ever clipped.

## Main tab

Identity block, unchanged in position: the sigil, the character's name, and beneath it `Level N · Human Fighter` in place of feature 019's bare `Level N`. Background appears in the detail grid rather than the heading, which would otherwise run long.

Two bars, not three (FR-032, FR-033 remove mana):

| Bar | Source |
|---|---|
| Health | `hp.cur` / `hp.max` |
| Experience | `xp.into_level` / `xp.to_next` |

The caption below the experience bar reads `N xp to level L+1`, or `Fully levelled` when `xp.maxed?` is true.

At level 20 `xp.to_next` is `nil`, and `hp_bar` divides `cur` by `max`, so passing it through unguarded is a division error rather than a full bar. The maxed case passes `cur` and `max` as the same positive number so the bar renders full. A level 20 render test covers this.

Detail grid, reusing the existing `.stats-grid` / `.stat-row` markup:

```
Armor Class      11        Speed              30 ft.
Initiative       +1        Size               Medium
Proficiency      +2        Hit Dice           1d10
Passive Perception 12      Background         Soldier
```

## Abilities tab

Three sections.

**Ability scores** — six rows, STR through CHA in canonical order, each showing the full ability name, the score, and the modifier with an explicit sign (FR-007).

**Saving throws** — six rows, same order, each showing the name, the modifier with sign, and a proficiency mark. Proficiency is conveyed by both a filled dot and the row's `aria-label`, never by color alone.

**Skills** — eighteen rows in alphabetical order by display name, each showing the skill name, its governing ability abbreviated, the modifier with sign, and the same proficiency mark.

Sign formatting is one helper. `+0` for zero, never a bare `0`, and never `+-1`.

## Spells tab

A single centered placeholder in the same muted style the empty inventory and empty quest log use:

> Spellcasting is not yet available.

No spell data, no slot table, no headings (FR-018).

## Sidebar HUD (FR-023)

The Character card loses its mana bar and keeps Health and Experience. `Level N` becomes `Level N Human Fighter`, matching the sheet heading. Nothing else about the card changes.

## Live updates (FR-024)

`PlayerStatsChanged` already arrives on `player:<id>` when XP is awarded or a level is gained. `GameLive.UIEvents.stats_changed/2` currently patches `:level` and `:xp` from the payload using `LevelCurve.progress/1`.

Patching is no longer enough: a level change moves proficiency bonus, maximum hitpoints, hit dice, every proficient save, and every proficient skill. So on a level change the handler re-reads `Stats.for_player/1` and replaces the whole `:stats` assign. On an XP-only change it keeps patching from the payload with `Srd.Rules.Experience.progress/1`, since nothing else can have moved.

One indexed primary-key read per level-up, which is rare. The XP-only path stays DB-free.

## What must not appear

- No mana value, bar, or caption anywhere (FR-033).
- No mock or hardcoded stat values (FR-022).
- No exact numbers on examine output (FR-025) — examine is untouched by this feature.

## Rendering tests

`test/agenticrealms_web/character_sheet_test.exs`:

- all three tab panels present in the rendered DOM, with `:main` visible;
- the main tab shows species, class, background, AC, initiative, speed, size, proficiency bonus, hit dice, and passive perception;
- the abilities tab renders 6 + 6 + 18 rows, with signs on every modifier;
- the spells tab renders the placeholder and no spell markup;
- the string `mana` (case-insensitive) appears nowhere in the sheet or the sidebar;
- a level-up message replaces the stats assign and the new proficiency bonus appears without a remount;
- a level 20 character renders `Fully levelled` and a full experience bar.
