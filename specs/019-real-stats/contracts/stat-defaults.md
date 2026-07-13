# Contract: Stat Defaults & NPC Freeze-at-Spawn

## Player defaults (at `PlayerSpawned`)

Set in `World.Player.apply(%PlayerSpawned{})` and mirrored by `PlayerStateProjector` on the same event:

| Stat | Default |
|---|---|
| `str,dex,con,int,wis,cha` | 12 |
| `level` | 1 |
| `xp` | 0 |
| `hp` / `max_hp` | 10 / 10 |
| `mana` / `max_mana` | 10 / 10 |

`PlayerSpawned` event shape is **unchanged** — defaults are code constants, not event payload.

## NPC blueprint base stats (authored)

`blueprints` (npc kind) carries base `str,dex,con,int,wis,cha` (default 12), `level` (default 1), `max_hp`, `max_mana` (default 10). Authored at **seed time** this milestone (no wizard UI). Object-kind blueprints ignore these columns.

## NPC freeze at spawn (contract)

At clone time, `commands.ex` puts stat keys into the `EntityCloned{fields}` map:

- **From blueprint**: `str..cha`, `level`, `max_hp`, `max_mana` copied from `bp`; `hp := max_hp`, `mana := max_mana` (start full).
- **Freeform NPC (no blueprint)**: defaults (abilities 12, level 1, `max_hp`/`max_mana` 10, `hp`/`mana` at max).

`EntityProjector.insert_npc/2` writes these into `npc_clones` (via tolerant `fval/2`, `on_conflict: :nothing`).

**Contract guarantees**:
- Each clone's stats are a frozen copy as of spawn; editing the blueprint later does not change existing clones (existing feature-008 guarantee, extended to stats).
- Each clone's `hp`/`mana` are per-instance and independent (FR-007) — two clones of one blueprint are separate rows.
- `EntityCloned` event schema is unchanged (stats ride in `fields`) — no event-store migration.

## Seed data

- Orchard/starter quest reward map (`seed.ex` `orchard_quests`) gains `"xp" => 100` so completing it reaches Level 2 (demonstrable loop; SC-003).
- Seeded NPC blueprints (Garrick, Amaranth) may optionally author non-default stats; absent authoring, they take the defaults above. Health-tier examine output can be exercised by authoring a clone/blueprint with `hp < max_hp` if a non-full tier is wanted in seed data.

## Migration

One read-model migration adds the columns above to `player_state` (+`xp`), `npc_clones` (no `xp`), and `blueprints` (base, no current `hp`/`mana`), each with the SQL default from the tables above so pre-existing rows are valid. World is re-seeded afterward (reseed-not-migrate; event log destroyable pre-launch).
