# Quickstart: Real Stats — Players & NPCs

Verify the three slices end-to-end: a real character sheet, XP/level-up from a quest, and examine health/power.

## Prerequisites

- PostgreSQL running (event store + read model).
- From repo root:

```bash
mix deps.get
mix ecto.reset        # drops, creates, migrates (incl. the new add_stats_columns migration), and reseeds the world
iex -S mix phx.server
```

`mix ecto.reset` re-seeds via `AgenticRealms.World.Seed.run/0`, which now materializes NPC clones with stat columns and authors `"xp" => 100` on the orchard quest reward (reseed-not-migrate; the event log is destroyable pre-launch).

## 1. A real character sheet (User Story 1 / SC-001, SC-002)

1. Register a new player at `http://localhost:4000` and enter the game (`/play`).
2. Open the **Character** card in the sidebar, then the **Character Sheet** modal.
3. **Expect**: your real username; **Level 1**; an Experience bar empty at the start (0 / 100 to next); **HP 10 / 10**; **Mana 10 / 10**; **STR/DEX/CON/INT/WIS/CHA all 12**.
4. **Expect NOT to see**: any class/deity line, the old "Veyr of Ashfall" name, a hardcoded "V" sigil (it should be your name's initial), "560 xp to level 8", or the "Channel Dawnlight / Regenerates slowly" captions. Nothing on the screen is a value other than name, level, XP, HP, mana, or an ability score.

## 2. Earn XP and level up (User Story 2 / SC-003, SC-004)

The seeded **orchard quest** ("The Orchard Keeper's Errand", from Amaranth) rewards **100 XP** + an item.

1. Travel to the orchard, `chat amaranth` and accept the quest in conversation.
2. Collect the three golden apples from the grove rooms (`take golden apple`), watching the Quest Log progress to 3/3.
3. Return and finalize with Amaranth (`chat amaranth` → turn in).
4. **Expect** in the log window: `You gain 100 experience.` **and** `You are now level 2!`
5. **Expect** the Character Sheet (live, without reopening) to show **Level 2**, Experience bar now measuring progress toward Level 3 (0 / 200), unchanged HP/mana/abilities (level-up grants no stat growth this milestone).
6. Negative check: a quest granting sub-threshold XP shows only the "You gain N experience." line, no level-up (SC-004).

### IEx shortcut (drive the award directly)

```elixir
alias AgenticRealms.World.{Commands, Stats}
pid = "<your player_id>"
Commands.award_xp(pid, 100, "manual:1")   # {:ok, ...}
Stats.for_player(pid)                       # => level: 2, xp progress toward level 3
Commands.award_xp(pid, 100, "manual:1")   # idempotent: same award_id → no change
Commands.award_xp(pid, 1000, "manual:2")  # multi-level jump → level jumps past several thresholds at once
```

## 3. Examine health & mettle (User Story 3 / SC-005, SC-006)

1. In a room with an NPC (e.g. Garrick), `examine garrick`.
2. **Expect** the description plus a health sentence (e.g. "Very healthy") and a relative-power phrase (e.g. "about as powerful" for a same-level NPC, or "too powerful to even compare" if the NPC is ≥ 4 levels above you).
3. **Expect NOT** to see any exact ability score, level, XP, or mana number for the target.
4. Examine another player in the room → same two qualitative lines, computed from their real stats.
5. `examine me` → your own detail with **no** relative-power phrase (self comparison omitted).

To exercise lower health tiers before combat exists, author an NPC blueprint/clone in `seed.ex` with `hp < max_hp` (e.g. hp 3 / max_hp 10 → "Very Weakened").

## 4. Persistence (SC-007)

Log out and back in; reopen the Character Sheet. **Expect** identical stats (level, XP, HP, mana, abilities) — they are rebuilt from the durable event store (players) and read model.

## Test suite

```bash
mix precommit    # compile --warnings-as-errors, format, test
```

Key suites: `level_curve_test`, `stats_banding_test` (pure), `player_award_xp_test` (award / multi-level jump / zero-XP no-op / idempotent re-award), `player_state_projector_stats_test`, `xp_awarder_test`, `entity_projector_npc_stats_test`, `examine_stats_test`, `quest_xp_threading_test`, and `character_sheet_render_test` (defaults + no mock values + live update).
