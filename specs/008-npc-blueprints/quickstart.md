# Quickstart: NPC Blueprints

Manual end-to-end verification of every user story in the spec after this feature ships. The refactor-only nature means most of these checks reproduce feature 007's behavior — that IS the validation for Story 1.

## Prereqs

```bash
mix ecto.reset           # runs all migrations including 008's; reseeds via Seed.run/0
mix phx.server           # localhost:4000
```

Confirm the server log includes both:

- `[World.Seed] starter map seeded`
- (On first start after migration) projector replay log lines indicating the event store was re-replayed.

## Story 1 — Players see no change (P1, SC-001 / SC-002)

This is the regression check: the feature is invisible to players.

1. Open `http://localhost:4000/` in browser A.
2. Register or log in as `alice`.
3. Click `Play`.
4. Verify the Stone Atrium's room view renders identically to feature 007:
   - **Objects**: contains `brass lantern — a dented brass lantern`.
   - **Other players**: empty on first login.
   - **Also here**: contains `Garrick the Innkeeper — a wiry innkeeper in a stained apron`.
5. Verify the `Also here:` section label is the exact literal text it was in feature 007.

6. Submit `look garrick`. Verify the `:detail :npc` entry renders Garrick's long description, character for character identical to feature 007:
   > A wiry man in a stained apron, his hands callused and his eyes patient. He polishes a tankard that already looks clean and watches the door without quite seeming to.

7. Submit `take Garrick the Innkeeper`. Verify `You can't take that.` appears.

8. Submit `examine the innkeeper`. (Triggers LLM resolver fallback.) Verify the same long description appears as in step 6.

If ANY of the above differs from feature 007's behavior, the refactor is wrong.

## Story 2 — A blueprint produced exactly one clone (P1, SC-002 / SC-004)

Query the persistence layer directly via IEx.

```elixir
iex> Repo.all(AgenticRealms.World.Schemas.NPCBlueprint)
[%NPCBlueprint{id: "garrick_the_innkeeper", name: "Garrick the Innkeeper", is_synthetic: false}]

iex> Repo.all(AgenticRealms.World.Schemas.NPCClone) |> Enum.map(&{&1.blueprint_id, &1.serial, &1.name})
[{"garrick_the_innkeeper", 1, "Garrick the Innkeeper"}]
```

Both queries MUST return exactly one row matching the expected shape. The blueprint's `is_synthetic` field MUST be `false` (the seed authored it explicitly).

Then test spawning a second clone of the same blueprint (this is the future-feature affordance proven now):

```elixir
iex> AgenticRealms.World.Commands.spawn_npc_clone(
...>   "garrick_the_innkeeper",
...>   AgenticRealms.World.Seed.starting_room_id(),
...>   Ecto.UUID.generate()
...> )
{:error, :clone_name_taken_in_room}
```

The refusal is correct — you can't have two Garricks in one room (FR-015). Try a different room:

```elixir
iex> AgenticRealms.World.Commands.spawn_npc_clone(
...>   "garrick_the_innkeeper",
...>   "00000000-0000-4000-8000-000000000002",   # North Corridor
...>   Ecto.UUID.generate()
...> )
{:ok, %{clone_id: _, serial: 2}}
```

A second clone of the same blueprint in a different room succeeds with `serial: 2`. The starter map now has two Garricks, one in each room. A player in the corridor would see Garrick in the "Also here" section.

(Reset with `mix ecto.reset` afterward to restore the clean seeded state.)

## Story 3 — Blueprint edits don't propagate to existing clones (P1, SC-003)

This is the defining property of full-copy semantics. Verified via direct DB write (FR-005a — no command path exposed).

```elixir
iex> [bp] = Repo.all(NPCBlueprint)
iex> bp.long_description
"A wiry man in a stained apron, his hands callused and his eyes patient. ..."

iex> [clone_before] = Repo.all(NPCClone)
iex> clone_before.long_description
"A wiry man in a stained apron, his hands callused and his eyes patient. ..."

# Mutate the blueprint directly.
iex> Repo.update_all(
...>   from(b in NPCBlueprint, where: b.id == "garrick_the_innkeeper"),
...>   set: [long_description: "ENTIRELY DIFFERENT LORE"]
...> )
{1, nil}

# Verify the blueprint changed.
iex> Repo.get(NPCBlueprint, "garrick_the_innkeeper").long_description
"ENTIRELY DIFFERENT LORE"

# But the clone is unchanged.
iex> Repo.get(NPCClone, clone_before.id).long_description
"A wiry man in a stained apron, his hands callused and his eyes patient. ..."
```

The clone's `long_description` MUST be unchanged. If it isn't, the projector is reading the blueprint at render time — which would violate I-3.

Reset with `mix ecto.reset` to restore.

## Story 4 — `<name>#<serial>` debug rendering (P2, SC-006)

The debug identity is admin/debug-only. Verified via IEx and by inspecting telemetry.

```elixir
iex> [clone] = Repo.all(NPCClone)
iex> AgenticRealms.World.Schemas.NPCClone.debug_id(clone)
"Garrick the Innkeeper#1"
```

To confirm player-facing surfaces don't include `#serial`:

1. Open browser A's session (already logged in).
2. View the page source for the rendered room view.
3. Confirm NO occurrence of `Garrick the Innkeeper#1` (or any `<name>#<digit>` pattern) appears in the HTML.

Telemetry check (via IEx, attaching a handler):

```elixir
:telemetry.attach(
  "debug-examine-watcher",
  [:agenticrealms, :examine, :resolve],
  fn _event, _measurements, metadata, _config ->
    IO.inspect(metadata, label: "examine telemetry")
  end,
  nil
)
```

Then in the browser, submit `look garrick`. The IEx console should show metadata including a `clone_debug_id` field with value `"Garrick the Innkeeper#1"`.

## Story 5 — Event-store replay (P2, SC-005)

This is the trickiest verification because it exercises the migration path.

Sequence:

1. Start fresh: `mix ecto.reset`.
2. Verify world state: 1 blueprint, 1 clone (as in Story 2).
3. From IEx, spawn a second NPC via the new command path (an authored blueprint + clone in a different room):
   ```elixir
   iex> WorldApp.dispatch(%CreateNPCBlueprint{
   ...>   blueprint_id: "maelyn_the_bard",
   ...>   name: "Maelyn the Bard",
   ...>   short_description: "a slender bard tuning a lute",
   ...>   long_description: "A slender woman in travelling leathers..."
   ...> })
   :ok

   iex> Commands.spawn_npc_clone(
   ...>   "maelyn_the_bard",
   ...>   "00000000-0000-4000-8000-000000000003",   # Library
   ...>   Ecto.UUID.generate()
   ...> )
   {:ok, %{clone_id: _, serial: 1}}
   ```
4. Verify: 2 blueprints, 2 clones (one in Atrium, one in Library).
5. Truncate the NPC tables to simulate a partial wipe:
   ```elixir
   iex> Repo.delete_all(NPCClone)
   iex> Repo.delete_all(NPCBlueprint)
   ```
6. Reset the WorldProjector subscription:
   ```elixir
   iex> Repo.query!("DELETE FROM subscriptions WHERE subscription_name = 'AgenticRealms.World.Projections.WorldProjector'")
   ```
7. Restart the application (`Ctrl-C Ctrl-C`, then `iex -S mix phx.server`).
8. Wait for the projector to catch up (a few seconds).
9. Verify the world state has been rebuilt:
   - `Repo.all(NPCBlueprint)` returns 2 rows: `garrick_the_innkeeper` and `maelyn_the_bard`.
   - `Repo.all(NPCClone)` returns 2 rows, each in their original rooms with `serial: 1`.
10. Run step 6-7 a second time (replay again). Verify the state is unchanged (idempotency).

If a developer's local environment has feature 007 historical events (e.g., from prior IEx-driven SpawnNPC dispatches before 008), step 7 will additionally produce synthetic blueprints (one per distinct (name, short, long) tuple from those historical events). The `is_synthetic: true` flag on those blueprints distinguishes them from the authored `garrick_the_innkeeper`.

## Negative cases

**Spawning a clone of an unknown blueprint**:
```elixir
iex> Commands.spawn_npc_clone(
...>   "nonexistent_blueprint_id",
...>   AgenticRealms.World.Seed.starting_room_id(),
...>   Ecto.UUID.generate()
...> )
{:error, :no_such_blueprint}
```
World state unchanged.

**Creating a blueprint with an empty long description**:
```elixir
iex> WorldApp.dispatch(%CreateNPCBlueprint{
...>   blueprint_id: "empty_test",
...>   name: "Test",
...>   short_description: "x",
...>   long_description: ""
...> })
{:error, :long_description_required}
```
No row inserted; aggregate refuses pre-emit.

**Creating a blueprint with a duplicate id**:
```elixir
iex> WorldApp.dispatch(%CreateNPCBlueprint{
...>   blueprint_id: "garrick_the_innkeeper",   # already exists from seed
...>   name: "Different Garrick",
...>   short_description: "x",
...>   long_description: "y"
...> })
{:error, :blueprint_already_exists}
```

## Test suite

```bash
mix test                                    # all unit tests, including the new NPCBlueprint aggregate tests
mix test --include integration              # all integration tests, including the renamed game_live_npc_test.exs
```

Both should pass with no modifications to assertions in feature 007's tests (FR-/SC-001 — only the setup fixtures may be updated to reference `Schemas.NPCClone` instead of `Schemas.NPC`).
