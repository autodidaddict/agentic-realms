# Quickstart / Verification: Entity Lifecycle — Clone & Move (016)

Manual + automated verification that the clone/move substrate works and that the retrofit did not
regress objects, take/drop, or NPCs. Run against a fresh dev seed (`mix ecto.reset`).

## Prerequisites
- `mix deps.get`, `mix compile --warnings-as-errors`, `mix ecto.reset` (reseeds via clone/move path).
- A promoted wizard account (`Accounts.promote_to_wizard/1`) for the wizard-spawn checks.

## A. Substrate happy paths (new capability)

1. **Clone into a room (US1).** As a wizard, spawn an object into your room. Expect: a co-present
   player sees `... appears.` (`RoomObjectArrived`) within ~2s (SC-001), and `examine` shows fields.
2. **Void state (US4).** Via `iex`, `clone_entity(:object, fields)` WITHOUT a move. Expect: the row
   exists with `container_type="void"`; the object appears in no room view and no inventory; no
   arrival was witnessed. Then `move_entity(id, ContainerRef.room(room_id), :relocated)` → it appears.
3. **Relocate room→room (US3).** Move an object from room A to room B. Expect: it leaves A and
   appears in B; it is in exactly one container.
4. **Move to void = removal.** `move_entity(id, ContainerRef.void(), :relocated)`. Expect: it leaves
   the room and is visible nowhere (used by quest consumption, R5).

## B. Retrofit non-regression (must be unchanged — US2 / SC-002)

5. **Seeded objects.** Fresh login: seeded objects are in their rooms and `examine` identically.
6. **take / inventory / drop.** `take <obj>` → object enters inventory, `inventory` lists it, other
   players in the room still see `RoomObjectTaken`; `drop <obj>` → returns to room, others see
   `RoomObjectDropped`. Behavior identical to pre-retrofit.
7. **Seeded NPCs.** Garrick appears in "Also here," `look garrick` shows lore-based long description,
   `take garrick` refused, entering his room fires his greeting (009), `chat garrick` replies in
   character (010).
8. **Quest flow (013).** Accept the orchard quest; quest items are placed (silently), collected, and
   on completion consumed (move-to-void) and the reward minted into inventory — end to end unchanged.

## C. Invariants & edges

9. **Exactly-one-container.** After any operation above, assert the entity's read row has exactly one
   container (void counts) — never two, never none.
10. **No-op move.** Move an object to the room it's already in → no `EntityMoved`, no witness.
11. **Name collision.** Cloning/moving an entity whose name collides in the destination room is
    refused (feature-007 rule; partial unique index backstop).
12. **Concurrent moves.** Fire two moves of the same entity to different rooms; terminal state is a
    single container (stream serialization).

## D. Automated gate (SC-002 / SC-003)

13. `mix test` green, including specs 006/007/008/009/010/013/014 suites and the take/drop/inventory
    suites — with only mechanical event-shape updates.
14. **One-model audit (SC-003):** grep confirms zero remaining `ObjectSpawned` / `ObjectPlacedInRoom`
    / `ObjectTakenFromRoom` / `ObjectDroppedInRoom` / `NPCClonedFromBlueprint` references in non-test
    code; placement flows exclusively through `EntityCloned` / `EntityMoved`.
