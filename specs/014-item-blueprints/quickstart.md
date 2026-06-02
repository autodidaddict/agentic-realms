# Quickstart: Wizard-Created Object Blueprints (Milestone 1)

This is the step-by-step verification path for milestone 1. Following these steps end-to-end exercises every user story (Stories 1–6) and every measurable success criterion (SC-001 through SC-009).

Prerequisites: a clean local dev environment with the existing seed (`mix phx.gen.seed` or equivalent), Postgres reachable, two browsers (or one browser + an incognito window) for the multi-witness checks.

## 1. Promote a player to a wizard

```bash
iex -S mix phx.server
```

In the iex prompt:

```elixir
# Promote whichever account you've signed up as.
{:ok, wizard} = AgenticRealms.Accounts.promote_to_wizard(1)
wizard.is_wizard
# => true

# Idempotent: calling again is safe.
AgenticRealms.Accounts.promote_to_wizard(1)
# => {:ok, %Player{is_wizard: true}}

# Unknown player id is refused.
AgenticRealms.Accounts.promote_to_wizard(999_999)
# => {:error, :not_found}
```

## 2. Sign in and confirm the Wizard switch appears

- Sign in as the promoted player in Browser 1.
- Top bar: the `Player / Wizard` switch IS visible.
- Sign in as a non-promoted player in Browser 2 (a separate account).
- Top bar: the switch is NOT visible.

This verifies FR-WIZ-3.

## 3. Enter trance (Story 1 — P1)

In Browser 1:

- Click `Wizard` on the top-bar switch. The wizard view loads in `:world` mode.
- Note the new sub-mode toggle in the wizard chrome (likely a button labeled "Enter trance" or similar). Click it.
- Browser 1's chrome swaps to Sanctum mode: world map hidden, current-room banner hidden, prompt placeholder reads `describe an archetype...`, footer shows two buttons (Discard, Commit).
- Browser 2 (a player co-located in Browser 1's wizard's room): system log entry appears: `<wizard username> enters a trance.`

This verifies FR-001, FR-002, FR-WIZ-4, and SC-003 (within 500 ms).

## 4. Author an Object Blueprint via prompt (Story 1 — P1)

Still in Sanctum (Browser 1):

- Type a multi-sentence prompt: *"a brass-bound chest, weather-beaten, carved with the seal of the Western Reach. Heavy. Fixed to whatever floor it sits on."*
- The Interpreted Data card progressively reveals:
  - `name`: `brass-bound chest`
  - `proposed_slug` (in the slug field, auto-derived): `brass_bound_chest`
  - `short_description`: some short variant of the prompt
  - `long_description`: the full prose
  - `fixed`: `true` (the LLM detects "fixed to whatever floor")
- Click `Commit`.
- The Blueprints registry shows the new row: `brass_bound_chest` @ revision 1.

This verifies FR-007 through FR-008, FR-019, FR-030, SC-001.

## 5. Exit trance (Story 1 — P1, continued)

- Click the mode toggle to return to World mode.
- Browser 2's log: `<wizard username> appears to come out of a trance.`

Verifies FR-003.

## 6. Spawn from blueprint (Story 2 — P1)

In Browser 1, World mode, standing in the same room:

- Open the Blueprints registry tab. The `brass_bound_chest` row shows with a `Spawn here` button.
- Click `Spawn here`.
- Browser 2's log: a `RoomObjectArrived` entry appears (the new chest).
- Browser 2: `look` — the chest is listed.
- Browser 2: `look brass-bound chest` — full `long_description` shown.
- Browser 2: `take brass-bound chest` — refused (the chest is `fixed: true`).

Verifies FR-010, FR-013 (no `blueprint_id` on the spawned object — verifiable by inspecting `world_objects` directly in iex), FR-029, SC-002.

```elixir
# In iex:
chest = AgenticRealms.Repo.get_by(AgenticRealms.World.Schemas.Object, name: "brass-bound chest")
Map.from_struct(chest) |> Map.keys() |> Enum.member?(:blueprint_id)
# => false (the schema doesn't have such a field)
```

## 7. Freeform create (Story 3 — P2)

In Browser 1, World mode:

- Open the world-mode prompt textarea.
- Type: *"a small clay pot, half-empty of dry barley, leaning against the wall"*.
- Wait for the Interpreted Data card to populate; click `Commit`.
- Browser 2: the clay pot appears in the room.
- The Blueprints registry has NO new row (freeform doesn't create a blueprint).

Verifies FR-011, FR-012.

## 8. Extract essence (Story 4 — P2)

In Browser 1, World mode:

- Click the clay pot in the room view. The focused-object panel appears with editable fields and an `Extract essence` button.
- Click `Extract essence`.
- Browser 1 flips to Sanctum mode (mode toggle shows the trance state).
- Browser 2's log: `<wizard username> enters a trance.`
- The Interpreted Data card opens with the chest's fields exactly populated; the slug is auto-derived as `small_clay_pot` (or similar — wizard can override before commit).
- Click `Commit`. The Blueprints registry gains a `small_clay_pot` row at revision 1.
- Switch to iex: query the clay pot's row again. Every field is byte-identical to before the extract.

Verifies FR-015 through FR-018, SC-004.

## 9. Edit a blueprint via form (Story 5 — P2)

Still in Sanctum:

- Click the `brass_bound_chest` row in the registry. The form populates with its current values.
- Edit `short_description` to add a bit. Click `Commit`.
- The registry row's revision bumps to 2.
- Query the existing chest in the world (the one spawned in Step 6): its `short_description` is UNCHANGED (it reflects revision 1's value at spawn time).
- Spawn a new chest via Spawn here on the row. The new chest carries the edited (revision 2) values.

Verifies FR-020, FR-021, SC-005, SC-006, SC-007.

## 10. Edit a world object via form (Story 5 — P2, continued)

In Browser 1, World mode:

- Click the original chest (the revision-1 one).
- In the focused-object panel, edit `short_description`.
- Click `Commit`.
- Browser 2: re-examine the chest. The new short description is visible.

Verifies FR-019, FR-020.

## 11. No-op commit on a blueprint (Story 5, edge)

In Sanctum, focus a blueprint:

- Open the form. Click `Commit` without changing any field.
- The registry row's revision does NOT bump.

Verifies FR-008.

## 12. Concurrent-edit conflict (FR-020a)

Open a second incognito window (Browser 3) signed in as another wizard (promote a second account via iex first). Both Browser 1 and Browser 3 enter Sanctum on the same Blueprint.

- Browser 1: edit `name`. Browser 3: edit `short_description`. Both clients still see revision N.
- Browser 1: click Commit. The Blueprint goes to revision N+1.
- Browser 3: click Commit. The commit fails with a stale-revision error. Browser 3's form reloads with the latest values (showing Browser 1's name change). Browser 3 reapplies their short-description change over the newer state and clicks Commit again — succeeds, revision N+2.

Verifies FR-020a, FR-020b.

## 13. Trance with no witness (FR-004)

In Browser 1, walk to a room with no other players. Toggle Sanctum on and off.

- No log entries are emitted anywhere (no co-present sessions to witness).
- In iex, replay the event log: `WizardEnteredTrance` and `WizardExitedTrance` events ARE present (the events fire regardless of witnesses; only the broadcaster suppresses the PubSub publish when no co-presence exists).

Verifies FR-004.

## 14. Disconnect mid-trance (FR-005)

In Browser 1, in Sanctum, close the browser tab.

- Browser 2 (co-present): NO `appears to come out of a trance` log entry is emitted.

Reconnect: the wizard returns in World mode (per FR-005), not Sanctum.

## 15. Authorization defenses (FR-WIZ-4, FR-WIZ-5)

In iex, simulate a non-wizard attempting a wizard-only command:

```elixir
{:error, :not_a_wizard} =
  AgenticRealms.World.Commands.create_object_blueprint(
    %{wizard_id: <non_wizard_id>, blueprint_id: "fake", name: "fake",
      short_description: "x", long_description: "x"},
    %{}
  )
```

The command is refused at the wrapper boundary; the aggregate is never reached.

In a crafted LiveView socket message (using `Phoenix.LiveViewTest`), push `toggle_authoring_mode` as a non-wizard. The handler refuses, the assigns are unchanged, no events are emitted.

## 16. Slug-collision UX (FR-007a, FR-007b)

In Sanctum, try to create a blueprint named `brass-bound chest` — auto-derived slug `brass_bound_chest` collides with the one from Step 4.

- The slug field surfaces an inline error: `slug already exists`.
- Commit button stays disabled until the wizard changes the slug.
- Edit the slug to `brass_bound_chest_v2`. Commit succeeds.

Verifies FR-007b, SC-009.

## 17. Sanity: registry doesn't expose Delete (Q2 clarification)

In the Blueprints registry, no row has a Delete button. No keyboard shortcut or context menu offers delete. The intent resolver's tool set does not include a delete tool — try a prompt like "remove the brass-bound chest blueprint" while in Sanctum; the resolver refuses with the no-actionable-intent hint.

Verifies the Q2 clarification.

## 18. Sanity: kind picker is gone (spec 001 amendment)

In Wizard mode (either sub-mode), there is no kind picker (`Room / NPC / Item / Quest / Spell` dropdown) in the chrome. The footer has exactly two buttons: Discard and Commit. No "Save as draft" button anywhere.

Verifies the Q3 clarification + the spec 001 amendments.

---

If every step above passes, milestone 1 is functionally complete. Run `mix test` to confirm the unit / integration / projector suites all pass; in particular, the new files under `test/agentic_realms/world/` and `test/agentic_realms_web/live/` cover the same scenarios more rigorously.
