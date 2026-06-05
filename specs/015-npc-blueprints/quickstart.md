# Quickstart / Verification: Wizard-Created NPC Blueprints (015)

Manual + automated verification, run against a fresh dev seed (`mix world.reset`). Builds on the
merged clone/move substrate (016) — spawning an NPC is `clone_into(room)`.

## Prerequisites
- `mix deps.get`, `mix compile --warnings-as-errors`, `mix world.reset` (seeds ≥2 toolsets + NPCs).
- A promoted wizard (`Accounts.promote_to_wizard/1`).

## A. NPC blueprint authoring (US1)
1. As a wizard, flip to trance, describe a character ("Garrick is a wiry innkeeper, a former soldier…").
2. Expect the Interpreted Data card to populate name/short/long/**lore**, any implied **behaviors**,
   and LLM-**proposed toolsets** pre-selected (grounded via `list_toolsets`).
3. Commit → an `npc`-kind blueprint exists in the registry at `revision: 1` with a name-derived slug.

## B. Toolsets compose (US4)
4. With ≥2 seeded toolsets (e.g. `orc`, `shopkeeper`), attach both via the picker + add one direct
   behavior. Commit. Effective behaviors = union of both toolsets ++ the direct behavior, no dupes
   dropped.
5. Spawn a clone (B below) and confirm it exhibits behaviors from both toolsets + the direct one.

## C. Spawn / freeform / edit / extract (US2/US5/US6/US7)
6. **Spawn here** on an NPC registry row → a clone appears in the wizard's room; a co-present player
   sees `<name> arrives.` and `look <name>` shows the long description; greeting behaviors fire (009);
   `chat <name>` replies in character grounded in the authored lore (010).
7. Edit the blueprint's lore + Commit → revision N→N+1; a previously-spawned clone is **unchanged**
   (full-copy).
8. Two wizards edit the same blueprint at revision N → first wins, second gets a stale-revision
   refusal showing the current revision.
9. **Freeform** an NPC in `:world` mode → appears in the room; no blueprint row added.
10. **Edit** an in-world NPC clone field in place → only that clone changes (co-present examine shows it).
11. **Extract essence** from an in-world NPC → trance card pre-fills name/descriptions/lore/behaviors/
    **toolset composition**; commit → new blueprint at revision 1; source clone byte-for-byte unchanged.

## D. Unified registry (US8)
12. Registry lists both `object` and `npc` blueprints with a visible kind; filtering to `npc` shows
    only NPC blueprints; "Spawn here" on an NPC row yields an NPC clone (not an object).

## E. Non-regression + automated gate
13. Seeded NPCs (Garrick) still appear, examine, are ungettable, greet, and converse (007–010 unchanged).
14. `mix test` green incl. the new aggregate/projector/wrapper/toolset/LiveView suites; slug-uniqueness
    spans both blueprint tables; effective-behaviors and extract-fidelity assertions pass.
