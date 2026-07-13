# Phase 0 Research: Real Stats — Players & NPCs

All `NEEDS CLARIFICATION` were resolved during `/speckit.clarify` (level-up scope, curve shape/cap, seed quest XP, band thresholds). This document records the **implementation** decisions taken during planning, each grounded in the current codebase.

---

## D1. Where do stats live? (aggregate vs. read model, per entity kind)

**Decision**: **Player stats are event-sourced aggregate state on `World.Player`. NPC stats are read-model-only, frozen onto `npc_clones` at spawn.**

**Rationale**:
- Player level/XP *change during play* (quest XP → level-up), so they are business state that must be the aggregate's (Principle II: the aggregate is the sole writer). `Player` already owns comparable in-aggregate state (`discovered_room_ids`) with snapshot serialization, so the pattern is proven (`lib/agenticrealms/world/player.ex:14-22, 115-131`).
- NPC stats *never mutate this milestone* — nothing deals damage yet (spec "No combat or spellcasting this milestone"). So NPCs need no stat events. Their stats are authored on the blueprint and frozen onto the clone at spawn via the existing full-copy denormalization: `commands.ex` `spawn_npc_clone_row/3` builds a `fields` map (`lib/agenticrealms/world/commands.ex:378-399`) that becomes `EntityCloned{fields}` and is written to `npc_clones` by `EntityProjector.insert_npc/2` (`lib/agenticrealms/world/projections/entity_projector.ex:142-164`).

**Alternatives considered**:
- *NPC stats as a stat aggregate now* — rejected: no mutation this milestone, so it would be an event stream that never emits after clone. Deferred to the combat milestone (which will need `Entity` damage events).
- *Player stats in the read model only* — rejected: violates Principle II (level/XP are business state changed by commands, not derivable projections).

---

## D2. Storage shape: flat columns vs. a jsonb `stats` map

**Decision**: **Flat integer columns** on `player_state`, `npc_clones`, and `blueprints`: `str, dex, con, int, wis, cha, level, hp, max_hp, mana, max_mana` (+ `xp` on `player_state` only; `blueprints` omits current `hp`/`mana`, carrying only base `max_hp`/`max_mana`).

**Rationale**: Matches the existing flat-column convention on `npc_clones` (`lib/agenticrealms/world/schemas/npc_clone.ex`) and `player_state`; trivial to render in the character sheet and to read in examine; queryable; no serialization ceremony. Ability **modifiers** (D&D `floor((score-10)/2)`) are *derived at display time*, not stored (FR-004: abilities don't influence outcomes yet, so modifiers are cosmetic).

**Alternatives considered**: a single jsonb `stats` map — rejected as premature abstraction (Principle VI/YAGNI); flat columns are simpler for read-model rendering and unit assertions.

---

## D3. What triggers the XP award, and how is it kept idempotent?

**Decision**: A **new named `Commanded.Event.Handler`** `World.Progression.XpAwarder` subscribes to `QuestCompleted{xp: n}` and, when `n > 0`, calls `Commands.award_xp(player_id, n, {:quest, quest_id})`. The Player aggregate dedupes by an **`award_id` MapSet** in aggregate state.

**Rationale**:
- The named-handler-reacts-and-dispatches pattern is exactly feature 018's `LifecycleManager` (`lib/agenticrealms/npc_minds/lifecycle_manager.ex:19-36`): a named handler is an **exclusive single cluster-wide subscriber**, giving "exactly one node awards each quest's XP" for free (Principle I) with no Horde machinery. The quest **projector** already demonstrates a handler issuing follow-on commands (`QuestProjector.handle(%QuestRewardMinted{})` dispatches `CloneEntity`+`MoveEntity`, `quest_projector.ex:49-90`), but a dedicated handler keeps the quest projector focused on the quest read model.
- Idempotency: Commanded delivers at-least-once, so a redelivered `QuestCompleted` (or a replay) must not double-award. The `AwardXp` command carries a deterministic `award_id` (the quest_id); the Player aggregate keeps `applied_award_ids :: MapSet` and returns `:ok` with **no event** if the id is already present — the identical idempotency mechanism as `discovered_room_ids`/`RecordRoomDiscovery` (`player.ex:75-88`). This makes award exactly-once per source under redelivery *and* full replay.

**Alternatives considered**:
- *Award inside `QuestProjector.handle(QuestCompleted)`* — workable (precedent exists) but mixes read-model projection with cross-aggregate progression and complicates the projector's idempotency story; a dedicated handler is cleaner and mirrors 018.
- *No dedup, rely on subscription checkpoint* — rejected: a crash between the `AwardXp` dispatch and the handler checkpoint would double-award; Principle II wants replay-safety, so dedup is on the aggregate.

**How XP reaches the event**: `commands.ex` `finalize_quest/2` already reads `inst.definition_snapshot["reward"]` (`commands.ex:747-749`); it will also read `reward["xp"]` and thread it through `%FinalizeQuest{reward_xp: n}` → the `Quest` aggregate emits `%QuestCompleted{..., xp: n}` (`quest.ex:77-112`). The reward passes through the accept-time snapshot untouched (`build_definition_snapshot/2`), so authoring `"xp" => 100` on the seed quest reward map "just works".

---

## D4. Level-up event modeling

**Decision**: `AwardXp` emits `[%PlayerXpAwarded{amount, new_total, award_id}]`, plus `%PlayerLeveledUp{from_level, to_level}` **only when** the recomputed level exceeds the current level. Two distinct events.

**Rationale**: The spec requires two distinct notices (XP-gain and level-up), and level-up is a "significant domain event" that SHOULD be observable (Principle VI). Two events let the witness broadcast each notice independently and let the projector update `xp` and `level` in their respective clauses. A single event carrying both deltas was considered but two events are more expressive and future-proof (the combat milestone will react to `PlayerLeveledUp` to grow max HP). `apply(PlayerXpAwarded)` records `xp` + the `award_id`; `apply(PlayerLeveledUp)` sets `level`.

---

## D5. Level-curve evaluation

**Decision**: A pure module `World.LevelCurve` implementing the clarified compounding quadratic `threshold(L) = 50·L² − 50·L` (cumulative XP to reach level L; `threshold(1)=0`), unbounded. Functions: `threshold(level)`, `level_for_xp(xp)` (largest L≥1 with `threshold(L) ≤ xp`, via the closed-form inverse floored, guaranteeing monotonicity), and `progress(xp)` → `%{level, into_level, to_next, fraction}` for the progress bar.

**Rationale**: Pure and DB-free ⇒ unit-tested first (Principle IV) and reusable by both the aggregate (to set level on award) and the read (`Stats.for_player` for the sheet's XP bar). Coefficients are module constants so the curve is tunable without touching call sites.

---

## D6. Examine data flow (health tier + relative power)

**Decision**: Compute the two phrases in the **pure `examine.ex` read facade** and carry them on the `Examine.Match` struct via new `:health_tier` and `:power_phrase` fields; the LiveView render layer only displays them.

**Rationale**: `examine/2` already receives the **examiner** as its `player_id` first arg and builds `Match` structs per target (`examine.ex:49-72, 200-236`). It will additionally load the examiner's `level` (one indexed read) and the target's `hp/max_hp/level` (already reading the target row for `long_description`), then call pure `Stats.health_tier(cur, max)` and `Stats.relative_power(examiner_level, target_level)`. Self-examination omits the power phrase (FR-021) — `examine.ex` already resolves self-aliases (`~w(__self__ me self)`, `examine.ex:40,60-65`), so the self branch simply leaves `:power_phrase` nil. The render sites (`player_commands.ex:135-187` build the `:detail` entry; `log_entry.ex:97-125` render it) append the two lines. Keeping the computation pure keeps it unit-testable and prevents number leakage in one place.

**Alternatives considered**: compute in `player_commands.ex` (has examiner id) — rejected: not unit-testable without the LiveView, and scatters the "never leak numbers" rule across web code.

---

## D7. Character-sheet read + live update

**Decision**: A `Stats.for_player/1` read returns the character-sheet shape `%{name, level, xp: %{into_level, to_next, fraction}, hp: %{cur,max}, mana: %{cur,max}, abilities: [%{name, value, modifier}]}`. `game_live.ex` mount assigns `:stats = Stats.for_player(player_id)` (replacing `GameData.player_stats/0` at `game_live.ex:196`; the modal's `GameData.ability_scores/0` at `player_modals.ex:21` is replaced by `stats.abilities`). Live updates: `UIEventBroadcaster` witnesses `PlayerXpAwarded`/`PlayerLeveledUp` → broadcasts a new `UIEvents.PlayerStatsChanged` on `Topics.player_topic(player_id)` → `game_live.ex` `handle_info` → `GameLive.UIEvents.stats_changed/2` updates the `:stats` assign and appends `:system` notice line(s).

**Rationale**: This is the exact real-data + live-update pattern already used for quests (`:quests` assign from `Quests.active_for/1`; `PlayerQuestFinalized` → `quest_finalized/2` updates assigns and appends a `:system` log line, `ui_events.ex:335-357`). The player already subscribes to `player_topic` at mount (`game_live.ex:96-99`). The `:system` log kind renders notices with zero new component code (`log_entry.ex:256`). The reusable `hp_bar/1` meter (`primitives.ex:14-34`) already supports `kind="xp"`.

---

## D8. Mock elements: replace vs. remove (reconciled with the spec)

**Decision**, per the finalized spec (mana is a **kept** real stat; class is **not** a stat):

| Mock element (location) | Action |
|---|---|
| `name` (`game_data.ex:68`) | **Replace** with the player's real username. |
| `hp`, `xp` (`game_data.ex:70,72`) | **Replace** with real values. |
| `mp` → **mana** (`game_data.ex:71`) | **Replace** with real current/max mana (mana is a defined stat, FR-016). |
| `ability_scores/0` (`game_data.ex:412-422`) | **Replace** with real STR/DEX/CON/INT/WIS/CHA (FR-001). |
| `class: "Cleric · lvl 7"` (`game_data.ex:69`; pills at `primitives.ex:125`, `player_modals.ex:34`) | **Remove** (no class stat in this feature). |
| Hardcoded sigil "V" (`primitives.ex:139`, `player_modals.ex:31`) | **Derive** from the real name's first letter. |
| Deity lore paragraph (`player_modals.ex:40-42`) | **Remove** (not a stat). |
| "560 xp to level 8" (`player_modals.ex:60`) | **Replace** with a value computed from `LevelCurve.progress/1`. |
| "Channel Dawnlight — 8 mp" / "Regenerates slowly while resting" (`player_modals.ex:48,53`) | **Remove** (flavor captions, not stats; nothing consumes mana yet). |

Once `player_stats/0` and `ability_scores/0` have no remaining callers, they are deleted from `game_data.ex` so no mock stat source lingers (SC-002).

---

## D9. Migration & existing data

**Decision**: One read-model migration `alter`s `player_state` (+`str,dex,con,int,wis,cha,level,xp,hp,max_hp,mana,max_mana`), `npc_clones` (+ same minus `xp`), and `blueprints` (+`str,dex,con,int,wis,cha,level,max_hp,max_mana`). Columns get sensible SQL defaults (abilities 12, level 1, xp 0, hp/max_hp 10, mana/max_mana 10) so pre-existing rows are valid. The world is then **re-seeded** (event log is destroyable pre-launch — see memory `event_log_destroyable_phase`), which re-materializes NPC clones with authored/default stats and re-runs player spawn defaults. No event-store migration.

**Rationale**: Consistent with the project's reseed-not-migrate policy and prior stat-column additions (`20260605120100_extend_npc_clones_authoring.exs`).

---

## Open items intentionally deferred to `/speckit.plan`'s consumer or later milestones

- **HP/mana display format** (numeric vs. bar) — plan uses the existing `hp_bar` meter; not a spec requirement.
- **When player stats initialize** — at `PlayerSpawned` (mount-time idempotent spawn); no separate account-creation hook needed.
- **NPC blueprint stat *authoring UI*** — seed-time only this milestone (no wizard surface), consistent with behavior-group authoring.
- **HP/mana mutation, stat growth on level-up, ability-score effects** — the combat milestone.
