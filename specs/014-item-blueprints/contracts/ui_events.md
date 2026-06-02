# UI Event Contracts: Wizard-Created Object Blueprints (Milestone 1)

`AgenticRealms.UIEventBroadcaster` is extended with handlers for the six new domain events. The broadcaster's pattern (existing): subscribe to events from the Commanded event store, project each event into one or more `Phoenix.PubSub` broadcasts on the appropriate topic, with no aggregate state of its own.

Topics used (existing helpers in `AgenticRealmsWeb.Topics`):
- `room:<room_id>` — co-present player notifications.
- `player:<player_id>` — per-player notifications (HUD updates, narrative log entries for the player's own actions).
- `blueprints` — NEW global topic for the wizard blueprint registry. Subscribers: wizard LiveView clients with the registry tab open.

## Outbound UI event: `RoomObjectArrived`

Triggered by: `ObjectSpawned`.

```elixir
%RoomObjectArrived{
  room_id: binary_id(),
  object_id: binary_id(),
  name: String.t(),
  short_description: String.t()
}
```

**Broadcast topic**: `room:<room_id>`.

**Player-side rendering** (in `GameLive.handle_info/2`): append a system log entry of the form `"<name> appears."` (or whatever the existing room-arrival pattern is) to every co-present player's narrative log. Also refresh the room's entity list so subsequent `look` calls show the new object.

Existing pattern reference: spec 007 FR-011 (NPC arrival). The Object-arrival entry follows the same shape.

## Outbound UI event: `RoomObjectEdited`

Triggered by: `ObjectEdited`.

```elixir
%RoomObjectEdited{
  room_id: binary_id(),
  object_id: binary_id(),
  fields_changed: map()
}
```

**Broadcast topic**: `room:<room_id>` (the room the object currently lives in).

**Player-side rendering**: refresh the room's entity list (if the object's `short_description` or `name` changed, the room view updates). Examination is read-against-DB; the next `look <target>` automatically sees the new values. No log entry is appended for an edit — wizard edits are quiet by design (no in-fiction notification to players that "the chest was modified"; players just see updated descriptions next time they look).

## Outbound UI event: `WizardBlueprintRegistryChanged`

Triggered by: `ObjectBlueprintCreated`, `ObjectBlueprintEdited`.

```elixir
%WizardBlueprintRegistryChanged{
  blueprint_id: String.t(),
  name: String.t(),
  short_description: String.t(),
  revision: integer(),
  event: :created | :edited
}
```

**Broadcast topic**: `blueprints` (global).

**Wizard-side rendering**: any wizard LiveView with the Blueprints registry tab open subscribes to this topic and patches the row in place. For `:created`, inserts a new row. For `:edited`, updates the existing row's name, short description, and revision in place. No full reload.

For a wizard whose currently-focused blueprint is the one being edited by *another wizard*, the LiveView additionally surfaces a banner: "This blueprint was just edited by another wizard. Your next Commit will fail with a stale-revision error — reload to see the latest." (This is a UX nicety; the actual stale-revision check happens at the aggregate per FR-020a.)

## Outbound UI event: `RoomSystemLogEntry` (extended use)

Triggered by: `WizardEnteredTrance`, `WizardExitedTrance`.

```elixir
%RoomSystemLogEntry{
  room_id: binary_id(),
  body: String.t(),    # "<wizard display name> enters a trance." etc.
  at: utc_datetime()
}
```

**Broadcast topic**: `room:<room_id>`.

**Player-side rendering**: append a `system` log entry to every co-present player's narrative log (matching feature 003's `system` entry styling — monospaced with a dot prefix per spec 001).

**Suppression rule** (FR-004): the broadcaster checks `Phoenix.Presence.list("room:<room_id>")` for other live player sessions. If only the wizard's own session is present, the broadcast is suppressed (no `RoomSystemLogEntry` PubSub publish). The wizard themselves does not see a "you enter a trance" entry in their own log — their chrome change is sufficient feedback.

The wizard's own session does NOT receive these entries — `RoomSystemLogEntry` is filtered against the recipient's `player_id` before render (matching the existing self-suppression pattern from feature 003's arrival witness).

## Wizard-side UI-only events (no PubSub topic — handled within the same LiveView)

These are LiveView event handlers responding to user clicks in the wizard view; they do not require PubSub because their effect is local to the wizard's own client.

### `phx-click="toggle_authoring_mode"`

Toggles `socket.assigns.authoring_mode` between `:world` and `:blueprints`. Side effect: invokes `AgenticRealms.World.WizardTrance.enter/2` or `.exit/2` which dispatches `WizardEnteredTrance` / `WizardExitedTrance` through the Commanded event store (which then projects to the `RoomSystemLogEntry` UI event above).

### `phx-click="commit_blueprint_draft"`

Reads the focused-blueprint form state, dispatches `Commands.create_object_blueprint/2` (if no `blueprint_id` is set in assigns) or `Commands.edit_object_blueprint/3` (if `blueprint_id` is set and the form has changes). On `{:ok, _}` clears the focused-blueprint assigns and reloads the registry. On `{:error, :stale_revision, current_revision: N}` re-reads the blueprint at revision N and re-renders the form with the latest values, surfacing a "your changes were not applied — the blueprint was edited by another wizard; reapply over the newer state" banner.

### `phx-click="discard_blueprint_draft"`

Clears the focused-blueprint form state. No server-side dispatch. Wizard remains in `:blueprints` mode.

### `phx-click="commit_object_edit"`

Same as `commit_blueprint_draft` but for the focused-world-object form state. Dispatches `Commands.edit_object/3`. No optimistic-lock concept for Objects in milestone 1 (Objects don't have a `revision` — they're freestanding and not subject to the same multi-author concurrent-edit pattern as Blueprints; if two wizards edit the same world Object simultaneously the second commit just overwrites the first — last-write-wins is acceptable for milestone 1 since the same-room two-wizard same-object scenario is rare and inconsequential compared to Blueprint edits which affect downstream spawn behavior).

### `phx-click="extract_essence"`

Triggers `Commands.extract_object_essence/3` with the focused-object's `id` and a proposed slug (auto-derived from the object's name; wizard can edit before commit). On `{:ok, blueprint_id}` flips `authoring_mode` to `:blueprints`, sets `focused_blueprint_id` to the new slug, populates the form. The mode-flip side-effect dispatches `WizardEnteredTrance`.

### `phx-click="spawn_here"` (on a registry row, world mode)

Dispatches `Commands.spawn_object_from_blueprint/3` with the registry row's `blueprint_id` and the wizard's current `room_id`. On `{:ok, _}` shows a brief toast "spawned" and the new Object appears in the room view via the `RoomObjectArrived` PubSub broadcast.

### `phx-click="focus_blueprint"` (on a registry row, either mode)

If `authoring_mode == :world`, flips to `:blueprints` (with trance entry side-effect). Sets `focused_blueprint_id` and loads the row's full payload into the form for editing.

### `phx-click="focus_object"` (on a room-view object entry, world mode)

Sets `focused_object_id`. Loads the world-object row into the form for editing. Reveals the "Extract essence" button.

## Authorization at every handler

Each LiveView event handler above begins with:

```elixir
def handle_event(_event, _params, %{assigns: %{is_wizard: false}} = socket) do
  {:noreply, put_flash(socket, :error, "wizard required")}
end
```

— defense-in-depth for FR-WIZ-4. The chrome that triggers these events is itself only rendered for wizards (FR-WIZ-3), but a crafted client message can still attempt to push the event; the handler guard refuses.

## Phoenix Presence touch-points

No new presence keys. The wizard's `authoring_mode` is NOT broadcast over presence — co-present players see trance entries via `RoomSystemLogEntry`, not via a per-player presence flag. (A future milestone may add a presence indicator like "in trance" next to the wizard's name in the room view, but that's deferred.)
