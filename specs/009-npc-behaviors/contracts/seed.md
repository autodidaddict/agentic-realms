# Contract: Seed Behavior Payloads

The seed extends two existing dispatch calls with `:behaviors` payloads. No new commands, no `Repo.update_all` for behaviors — all behavior data flows through the existing event-sourced creation events.

## Garrick the Innkeeper — NPC blueprint

The existing `Seed.do_seed/0` block that dispatches `CreateNPCBlueprint` for Garrick gains a `:behaviors` field on the command struct:

```elixir
garrick_behaviors = [
  %{
    "trigger" => "player_entered",
    "actions" => [
      %{"type" => "say", "text" => "Welcome to the Stone Atrium."}
    ]
  },
  %{
    "trigger" => "player_left",
    "actions" => [
      %{"type" => "say", "text" => "Farewell, traveler."}
    ]
  }
]

:ok = Behaviors.Validator.validate(garrick_behaviors)

:ok =
  WorldApp.dispatch(
    %CreateNPCBlueprint{
      blueprint_id: @innkeeper_garrick_blueprint_id,
      name: "Garrick the Innkeeper",
      short_description: "a wiry innkeeper in a stained apron",
      long_description:
        "A wiry man in a stained apron, his hands callused and his eyes patient. He polishes a tankard that already looks clean and watches the door without quite seeming to.",
      behaviors: garrick_behaviors
    },
    consistency: :strong
  )

# Then the existing spawn_npc_clone call — unchanged. The clone inherits
# the behaviors via the full-copy at the moment of spawn.
{:ok, _} =
  WorldCommands.spawn_npc_clone(
    @innkeeper_garrick_blueprint_id,
    @starting_room_id,
    @innkeeper_garrick_clone_id
  )
```

The `Validator.validate/1` call before dispatching is the fail-fast layer — if the seed author mistypes a trigger or omits the text field, the seed crashes during `mix ecto.reset` with a clear `{:error, _}` reason.

## Stone Atrium — room behaviors

The existing `CreateRoom` dispatch for the Stone Atrium gains a `:behaviors` field:

```elixir
atrium_behaviors = [
  %{
    "trigger" => "player_entered",
    "actions" => [
      %{"type" => "say", "text" => "The cool air carries the scent of rain."}
    ]
  }
]

:ok = Behaviors.Validator.validate(atrium_behaviors)

:ok =
  WorldApp.dispatch(
    %CreateRoom{
      room_id: @starting_room_id,
      name: "Stone Atrium",
      description:
        "A wide, pillared hall of mossy granite. The air is cool and tastes faintly of rain. A single shaft of daylight falls from a slot high above, lighting motes of dust drifting in slow spirals.",
      behaviors: atrium_behaviors
    },
    consistency: :strong
  )
```

The North Corridor and Dusty Library `CreateRoom` dispatches stay unchanged (no `:behaviors` field, defaults to `[]`). They have no behaviors in this feature.

## Required deployment posture

After this feature ships, developers MUST run `mix event_store.reset && mix ecto.reset` to rebuild the world with the new behavior-carrying events. The same posture as feature 008's wipe-and-replay migration (FR-021a). Developers who pulled feature 008 already did this once; doing it again for feature 009 is the same workflow.

For deployed instances (none yet at this project's stage), the deployment runbook calls for:

1. Apply migration (adds the three `behaviors` JSONB columns with `DEFAULT '[]'::jsonb`).
2. Reset event-store subscriptions and replay (per feature 008's documented procedure).
3. The replay processes existing `RoomCreated`, `NPCBlueprintCreated`, `NPCClonedFromBlueprint` events with their legacy (no-behaviors) payloads — every entity rebuilds with `behaviors: []`.
4. To actually populate the seeded behaviors, the operator must additionally re-run the seed (or accept that the deployment doesn't have them — depending on whether they re-seed).

For dev workflow this is straightforward; for production we'd document it more rigorously when that becomes a concern.

## Validator integration

The seed calls `Behaviors.Validator.validate/1` for each behavior list it intends to dispatch. A `{:error, reason}` from the validator raises and halts the seed:

```elixir
case Behaviors.Validator.validate(garrick_behaviors) do
  :ok -> :ok
  {:error, reason} -> raise "Seed authoring error in garrick_behaviors: #{inspect(reason)}"
end
```

This is the only place the validator is called in this feature. Future authoring surfaces (wizard tab) will reuse it.

## Test verification

The integration test (`test/agenticrealms_web/live/game_live_behaviors_test.exs`) starts with `Seed.run/0` and immediately verifies:

1. The seeded Garrick blueprint row has the expected `behaviors` list (Story 4 acceptance).
2. The seeded Garrick clone row has the same behaviors (full-copy verification).
3. The Stone Atrium row has the atmospheric narration behavior.

Then the test proceeds to exercise the firing path end-to-end via player logins and movements.
