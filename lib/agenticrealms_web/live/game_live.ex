defmodule AgenticRealmsWeb.GameLive do
  use AgenticRealmsWeb, :live_view

  import AgenticRealmsWeb.GameComponents

  alias AgenticRealms.Accounts
  alias AgenticRealms.GameData

  alias AgenticRealms.World.{
    Commands,
    CommandParser,
    Communication,
    Direction,
    Examine,
    IntentResolver,
    MapView,
    Queries,
    Quests,
    Seed
  }

  alias AgenticRealms.World.Examine.Match, as: ExamineMatch

  alias AgenticRealms.World.UIEvents.{
    RoomPlayerArrived,
    RoomPlayerLeft,
    RoomObjectTaken,
    RoomObjectDropped,
    RoomObjectArrived,
    RoomObjectEdited,
    RoomNPCArrived,
    RoomTranceEntered,
    RoomTranceExited,
    WizardBlueprintRegistryChanged,
    BehaviorUtterance,
    PlayerCurrentRoomChanged,
    PlayerInventoryChanged,
    PlayerQuestAccepted,
    PlayerQuestProgress,
    PlayerQuestFinalized,
    RoomUtterance,
    PrivateUtterance
  }

  alias AgenticRealmsWeb.Presence
  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub

  @impl true
  def mount(_params, _session, socket) do
    player_id = socket.assigns.current_player.id
    username = socket.assigns.current_player.username

    :ok =
      case Commands.spawn(player_id, Seed.starting_room_id()) do
        {:ok, _} -> :ok
        {:error, :already_spawned} -> :ok
      end

    {current_room_id, room_view} =
      case Queries.look_room(player_id) do
        {:ok, view} ->
          {view.id, view}

        {:error, reason} ->
          raise "GameLive mount: look_room/1 returned #{inspect(reason)} for player #{player_id} after spawn — read model and aggregate are desynced (likely FR-022)"
      end

    inventory = Queries.list_inventory(player_id)
    presence = Queries.other_occupants_of(current_room_id, player_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(@pubsub, Topics.player_topic(player_id))
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(current_room_id))
      Phoenix.PubSub.subscribe(@pubsub, Presence.topic())

      # Feature 014 US6 — every wizard session subscribes to the global
      # blueprints topic for live registry updates from other wizards.
      if socket.assigns.current_player.is_wizard do
        Phoenix.PubSub.subscribe(@pubsub, Topics.blueprints_topic())
      end

      {:ok, _} = Presence.track_player(self(), player_id, username)

      # Feature 009 — fire `player_entered` behaviors for this session's
      # arrival in the player's current room. Behaviors fire on EVERY
      # connected mount, not just first-time spawn (a re-mounting session
      # is "arriving" again from the room/NPC's perspective). PlayerMoved
      # events drive subsequent in-session arrivals via the interpreter's
      # event-handler clause.
      AgenticRealms.World.Behaviors.Interpreter.fire_for_arrival(
        player_id,
        current_room_id
      )
    end

    {:ok,
     socket
     |> assign(:mode, :player)
     # Feature 014 — wizard authorization + trance mode. `:is_wizard` is
     # the FR-WIZ-1 flag; `:authoring_mode` is the world/blueprints
     # sub-mode within Wizard view (only meaningful when :is_wizard and
     # :mode == :wizard). Non-wizards never see the top-bar Wizard
     # switch (FR-WIZ-3), enforced by the layout.
     |> assign(:is_wizard, socket.assigns.current_player.is_wizard)
     |> assign(:authoring_mode, if(socket.assigns.current_player.is_wizard, do: :world, else: nil))
     |> assign(:focused_object_id, nil)
     |> assign(:focused_blueprint_id, nil)
     # Feature 014 US1 — blueprint authoring state. Populated by the
     # LLM resolver on submit_wizard_prompt; refined by the wizard via
     # form fields; committed via commit_blueprint_draft (US1) or edited
     # in place via the edit flow that lands in US5.
     |> assign(:focused_blueprint_draft, nil)
     |> assign(:focused_object_draft, nil)
     |> assign(:focused_object_edit, nil)
     |> assign(:wizard_prompt, "")
     |> assign(:wizard_resolver_task, nil)
     |> assign(:wizard_input_locked, false)
     |> assign(:blueprint_commit_error, nil)
     |> assign(:last_spawn, nil)
     |> assign(:current_room_name, Map.get(room_view, :name))
     |> assign(
       :object_blueprints,
       if(socket.assigns.current_player.is_wizard, do: Queries.list_object_blueprints(), else: [])
     )
     |> assign(
       :room_objects,
       if(socket.assigns.current_player.is_wizard,
         do: Queries.list_objects_in_room_for_wizard(current_room_id),
         else: []
       )
     )
     |> assign(:modal, nil)
     |> assign(:map_open, false)
     |> assign(:map_view, MapView.for_player(player_id))
     |> assign(:log, [%{kind: :room, room: room_view}])
     |> assign(:current_room_id, current_room_id)
     |> assign(:input, "")
     |> assign(:streaming, false)
     # Per-LiveView opaque id for actor-side self-filtering of own broadcasts
     # (FR-005: speaker's own session does not render the witness broadcast it
     # produced). See specs/004-player-communication/contracts/ui_events.md.
     |> assign(:session_id, make_ref())
     # Feature 005 — natural-language intent resolution. `resolver_task`
     # tracks an in-flight async LLM call; `input_locked` disables the
     # command input while it runs.
     |> assign(:resolver_task, nil)
     |> assign(:input_locked, false)
     |> assign(:stats, GameData.player_stats())
     |> assign(:inventory, inventory)
     # Feature 013 — Quests. `:quests` is the active-quest list rendered
     # in the HUD card with per-criterion progress lines; `:completed_quests`
     # backs the Completed section of the quest modal and is retained
     # indefinitely (FR-025).
     |> assign(:quests, Quests.active_for(player_id))
     |> assign(:completed_quests, Quests.history_for(player_id))
     |> assign(:presence, presence)
     |> assign(:selected_quest, 0)
     |> assign(:wizard_kind, :item)
     |> assign(:wizard_text, GameData.starter_prompts()[:item])
     |> assign(:wizard_user_edited, false)
     |> assign(:wizard_examples, GameData.wizard_examples())
     |> assign(:open_trigger, nil)
     |> assign(:tweaks, build_tweaks(socket.assigns.current_player))}
  end

  @impl true
  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    new_mode = String.to_existing_atom(mode)
    # FR-WIZ-3 / FR-WIZ-4 — non-wizards must not be able to enter Wizard
    # view, even via a crafted client event. The top-bar switch is
    # already hidden for them by the layout; this is defense-in-depth.
    if new_mode == :wizard and not socket.assigns.is_wizard do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :mode, new_mode)}
    end
  end

  # Feature 014 — wizard authoring mode toggle (FR-001 / FR-002 / FR-003).
  # Flips `:authoring_mode` between `:world` and `:blueprints` and side-
  # effects a transient broadcast on the wizard's current `room:` topic.
  # No verb to type — the toggle IS the affordance.
  def handle_event(
        "toggle_authoring_mode",
        _params,
        %{assigns: %{is_wizard: true, mode: :wizard}} = socket
      ) do
    wizard_id = socket.assigns.current_player.id
    wizard_username = socket.assigns.current_player.username
    room_id = socket.assigns.current_room_id

    case socket.assigns.authoring_mode do
      :world ->
        :ok = AgenticRealms.World.WizardTrance.enter(wizard_id, wizard_username, room_id)

        {:noreply,
         socket
         |> assign(:authoring_mode, :blueprints)
         |> assign(:last_spawn, nil)}

      :blueprints ->
        :ok = AgenticRealms.World.WizardTrance.exit(wizard_id, wizard_username, room_id)

        {:noreply,
         socket
         |> assign(:authoring_mode, :world)
         |> assign(:focused_blueprint_id, nil)}
    end
  end

  def handle_event("toggle_authoring_mode", _params, socket), do: {:noreply, socket}

  # Feature 014 US1 — phx-change for the wizard's authoring-mode prompt
  # textarea. Captures the current text so the wizard can navigate away
  # and back without losing it within a single trance session.
  def handle_event("update_wizard_prompt", %{"text" => text}, socket) do
    {:noreply, assign(socket, :wizard_prompt, text)}
  end

  # Feature 014 US1 / US3 — submit the wizard's prompt to the LLM
  # resolver. Branches on :authoring_mode: :blueprints uses the wizard-
  # blueprint resolver (extracts archetype fields), :world uses the
  # freeform Object resolver (extracts one-off Object fields). Both
  # follow the same supervised-async pattern: lock input, stash task
  # ref + raw, handle_info finishes. Prompt stays visible in the
  # textarea so the wizard can compare it against the extracted draft.
  def handle_event(
        "submit_wizard_prompt",
        %{"text" => raw},
        %{
          assigns: %{
            is_wizard: true,
            mode: :wizard,
            authoring_mode: am,
            wizard_input_locked: false
          }
        } = socket
      )
      when am in [:blueprints, :world] do
    player_id = socket.assigns.current_player.id

    resolver_fun =
      case am do
        :blueprints -> :resolve_wizard_blueprint
        :world -> :resolve_wizard_world
      end

    task =
      Task.Supervisor.async_nolink(
        AgenticRealms.IntentResolverTaskSupervisor,
        IntentResolver,
        resolver_fun,
        [player_id, raw]
      )

    {:noreply,
     socket
     |> assign(:wizard_resolver_task, %{ref: task.ref, raw_input: raw, mode: am})
     |> assign(:wizard_input_locked, true)
     |> assign(:wizard_prompt, raw)}
  end

  def handle_event("submit_wizard_prompt", _, socket), do: {:noreply, socket}

  # Feature 014 US1 — phx-change for the focused-blueprint draft form.
  # Accepts the whole `draft[...]` form payload so a single change event
  # captures the wizard's edits across all four fields plus the slug.
  # Slug auto-derives from name until the wizard explicitly edits it.
  def handle_event(
        "update_blueprint_draft",
        %{"draft" => params},
        %{assigns: %{is_wizard: true, focused_blueprint_draft: draft}} = socket
      )
      when not is_nil(draft) do
    new_name = Map.get(params, "name", draft.name) || ""
    slug_input = Map.get(params, "proposed_slug", "") || ""

    # The slug input itself is the source of truth: blank input means
    # "auto-derive from name", anything else is the wizard's explicit
    # override. No separate sticky flag — clearing the field and then
    # renaming the blueprint correctly re-derives.
    proposed_slug =
      if slug_input == "" do
        AgenticRealms.World.ObjectBlueprint.Slug.derive(new_name)
      else
        slug_input
      end

    updated =
      draft
      |> Map.put(:name, new_name)
      |> Map.put(:short_description, Map.get(params, "short_description", draft.short_description) || "")
      |> Map.put(:long_description, Map.get(params, "long_description", draft.long_description) || "")
      |> Map.put(:fixed, Map.get(params, "fixed") == "true")
      |> Map.put(:proposed_slug, proposed_slug)

    {:noreply,
     socket
     |> assign(:focused_blueprint_draft, updated)
     |> assign(:blueprint_commit_error, nil)}
  end

  def handle_event("update_blueprint_draft", _, socket), do: {:noreply, socket}

  # Feature 014 US1 + US5 — commit the focused blueprint draft.
  # Branches on whether the draft carries `:expected_revision`:
  #   * nil → CREATE path (US1) → Commands.create_object_blueprint/2
  #   * integer → EDIT path (US5) → Commands.edit_object_blueprint/3
  # On stale-revision the form re-loads with the latest persisted
  # state and surfaces a banner.
  def handle_event(
        "commit_blueprint_draft",
        _params,
        %{assigns: %{is_wizard: true, focused_blueprint_draft: draft}} = socket
      )
      when not is_nil(draft) do
    case Map.get(draft, :expected_revision) do
      nil -> commit_blueprint_create(socket, draft)
      revision when is_integer(revision) -> commit_blueprint_edit(socket, draft, revision)
    end
  end

  def handle_event("commit_blueprint_draft", _, socket), do: {:noreply, socket}

  # Feature 014 US5 — click a Blueprint registry row to focus it for
  # editing. If the wizard isn't already in :blueprints mode, flip
  # there (firing the trance entry as a side effect).
  def handle_event(
        "focus_blueprint",
        %{"blueprint_id" => blueprint_id},
        %{assigns: %{is_wizard: true, mode: :wizard}} = socket
      )
      when is_binary(blueprint_id) do
    case Queries.get_object_blueprint(blueprint_id) do
      nil ->
        {:noreply, assign(socket, :blueprint_commit_error, :unknown_blueprint)}

      bp ->
        draft = %{
          blueprint_id: bp.id,
          name: bp.name,
          short_description: bp.short_description,
          long_description: bp.long_description,
          fixed: bp.fixed,
          proposed_slug: bp.id,
          expected_revision: bp.revision
        }

        socket =
          if socket.assigns.authoring_mode == :world do
            :ok =
              AgenticRealms.World.WizardTrance.enter(
                socket.assigns.current_player.id,
                socket.assigns.current_player.username,
                socket.assigns.current_room_id
              )

            socket
            |> assign(:authoring_mode, :blueprints)
            |> assign(:last_spawn, nil)
          else
            socket
          end

        {:noreply,
         socket
         |> assign(:focused_blueprint_draft, draft)
         |> assign(:focused_object_draft, nil)
         |> assign(:focused_object_edit, nil)
         |> assign(:focused_blueprint_id, bp.id)
         |> assign(:blueprint_commit_error, nil)}
    end
  end

  def handle_event("focus_blueprint", _, socket), do: {:noreply, socket}

  # Feature 014 US5 — focus a world Object for in-place editing.
  def handle_event(
        "focus_object_for_edit",
        %{"object_id" => object_id},
        %{
          assigns: %{
            is_wizard: true,
            mode: :wizard,
            authoring_mode: :world,
            current_room_id: room_id
          }
        } = socket
      )
      when is_binary(object_id) do
    case AgenticRealms.World.Queries.get_object_for_wizard(object_id) do
      nil ->
        {:noreply, assign(socket, :blueprint_commit_error, :unknown_object)}

      %{room_id: ^room_id} = obj ->
        edit = %{
          object_id: obj.id,
          name: obj.name || "",
          short_description: obj.short_description || "",
          long_description: obj.long_description || "",
          fixed: obj.fixed == true
        }

        {:noreply,
         socket
         |> assign(:focused_object_edit, edit)
         |> assign(:focused_object_draft, nil)
         |> assign(:blueprint_commit_error, nil)}

      _other_room ->
        {:noreply, assign(socket, :blueprint_commit_error, :object_not_in_room)}
    end
  end

  def handle_event("focus_object_for_edit", _, socket), do: {:noreply, socket}

  # Feature 014 US5 — phx-change for the focused-object edit form.
  def handle_event(
        "update_object_edit",
        %{"edit" => params},
        %{assigns: %{is_wizard: true, focused_object_edit: edit}} = socket
      )
      when not is_nil(edit) do
    updated = %{
      object_id: edit.object_id,
      name: Map.get(params, "name", edit.name) || "",
      short_description: Map.get(params, "short_description", edit.short_description) || "",
      long_description: Map.get(params, "long_description", edit.long_description) || "",
      fixed: Map.get(params, "fixed") == "true"
    }

    {:noreply,
     socket
     |> assign(:focused_object_edit, updated)
     |> assign(:blueprint_commit_error, nil)}
  end

  def handle_event("update_object_edit", _, socket), do: {:noreply, socket}

  # Feature 014 US5 — commit the focused object edit. Dispatches
  # Commands.edit_object/3; on success refreshes the room-objects
  # panel so the (possibly renamed) row reflects the new values.
  def handle_event(
        "commit_object_edit",
        _params,
        %{
          assigns: %{
            is_wizard: true,
            mode: :wizard,
            authoring_mode: :world,
            focused_object_edit: edit
          }
        } = socket
      )
      when not is_nil(edit) do
    fields_changed = %{
      name: edit.name,
      short_description: edit.short_description,
      long_description: edit.long_description,
      fixed: edit.fixed
    }

    case AgenticRealms.World.Commands.edit_object(
           socket.assigns.current_player.id,
           edit.object_id,
           fields_changed
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:focused_object_edit, nil)
         |> assign(:blueprint_commit_error, nil)
         |> refresh_room_objects()}

      {:error, reason} ->
        {:noreply, assign(socket, :blueprint_commit_error, reason)}
    end
  end

  def handle_event("commit_object_edit", _, socket), do: {:noreply, socket}

  def handle_event("discard_object_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:focused_object_edit, nil)
     |> assign(:blueprint_commit_error, nil)}
  end

  # Feature 014 US1 — discard the in-flight blueprint draft. Wizard
  # stays in :blueprints mode (the trance does not auto-end).
  def handle_event("discard_blueprint_draft", _, socket) do
    {:noreply,
     socket
     |> cancel_wizard_resolver_task()
     |> assign(:focused_blueprint_draft, nil)
     |> assign(:blueprint_commit_error, nil)}
  end

  # Feature 014 US3 — phx-change for the freeform-object draft form.
  # Same shape as update_blueprint_draft but only carries the four
  # Object fields (no slug — Objects don't have slugs).
  def handle_event(
        "update_object_draft",
        %{"draft" => params},
        %{assigns: %{is_wizard: true, focused_object_draft: draft}} = socket
      )
      when not is_nil(draft) do
    updated = %{
      name: Map.get(params, "name", draft.name) || "",
      short_description: Map.get(params, "short_description", draft.short_description) || "",
      long_description: Map.get(params, "long_description", draft.long_description) || "",
      fixed: Map.get(params, "fixed") == "true"
    }

    {:noreply,
     socket
     |> assign(:focused_object_draft, updated)
     |> assign(:blueprint_commit_error, nil)}
  end

  def handle_event("update_object_draft", _, socket), do: {:noreply, socket}

  # Feature 014 US3 — commit the focused freeform-object draft. Spawns
  # the Object into the wizard's current room via SpawnObjectFreeform
  # — no Object Blueprint involvement, no registry change.
  def handle_event(
        "commit_object_draft",
        _params,
        %{assigns: %{is_wizard: true, mode: :wizard, authoring_mode: :world, focused_object_draft: draft}} = socket
      )
      when not is_nil(draft) do
    attrs = %{
      name: Map.get(draft, :name, ""),
      short_description: Map.get(draft, :short_description, ""),
      long_description: Map.get(draft, :long_description, ""),
      fixed: Map.get(draft, :fixed, false)
    }

    case AgenticRealms.World.Commands.spawn_object_freeform(
           socket.assigns.current_player.id,
           socket.assigns.current_room_id,
           attrs
         ) do
      {:ok, object_id} ->
        feedback = %{
          object_id: object_id,
          blueprint_id: nil,
          name: attrs[:name],
          room_name: socket.assigns.current_room_name,
          at: System.monotonic_time(:millisecond)
        }

        {:noreply,
         socket
         |> assign(:focused_object_draft, nil)
         |> assign(:blueprint_commit_error, nil)
         |> assign(:wizard_prompt, "")
         |> assign(:last_spawn, feedback)}

      {:error, reason} ->
        {:noreply, assign(socket, :blueprint_commit_error, reason)}
    end
  end

  def handle_event("commit_object_draft", _, socket), do: {:noreply, socket}

  # Feature 014 US3 — discard the in-flight freeform-object draft.
  def handle_event("discard_object_draft", _, socket) do
    {:noreply,
     socket
     |> cancel_wizard_resolver_task()
     |> assign(:focused_object_draft, nil)
     |> assign(:blueprint_commit_error, nil)}
  end

  # Feature 014 US4 — extract essence from a world Object (FR-015,
  # FR-016, FR-018). Flips the wizard into :blueprints mode (trance
  # entries fire via WizardTrance.enter), pre-populates the focused
  # blueprint draft with a WHOLESALE copy of the source object's
  # settable fields plus an auto-derived slug. Source object is NOT
  # modified — the actual blueprint creation happens later when the
  # wizard clicks Commit through the existing commit_blueprint_draft
  # path.
  def handle_event(
        "extract_essence",
        %{"object_id" => object_id},
        %{
          assigns: %{
            is_wizard: true,
            mode: :wizard,
            authoring_mode: :world,
            current_room_id: room_id
          }
        } = socket
      )
      when is_binary(object_id) do
    case AgenticRealms.World.Queries.get_object_for_wizard(object_id) do
      nil ->
        {:noreply, assign(socket, :blueprint_commit_error, :unknown_object)}

      %{room_id: ^room_id} = object ->
        slug = AgenticRealms.World.ObjectBlueprint.Slug.derive(object.name || "")

        draft = %{
          name: object.name || "",
          short_description: object.short_description || "",
          long_description: object.long_description || "",
          fixed: object.fixed == true,
          proposed_slug: slug
        }

        :ok =
          AgenticRealms.World.WizardTrance.enter(
            socket.assigns.current_player.id,
            socket.assigns.current_player.username,
            room_id
          )

        {:noreply,
         socket
         |> assign(:authoring_mode, :blueprints)
         |> assign(:focused_blueprint_draft, draft)
         |> assign(:focused_object_draft, nil)
         |> assign(:focused_object_id, object_id)
         |> assign(:blueprint_commit_error, nil)
         |> assign(:last_spawn, nil)}

      _other_room ->
        # The object exists but is in a different room (likely picked up
        # by a player). Can't extract from things not co-located.
        {:noreply, assign(socket, :blueprint_commit_error, :object_not_in_room)}
    end
  end

  def handle_event("extract_essence", _, socket), do: {:noreply, socket}

  # Feature 014 US2 — spawn a clone of a registry blueprint into the
  # wizard's current room. Only valid while in World mode (FR-027).
  # The arrival broadcast comes back through PubSub as a
  # RoomObjectArrived UI event which appends a system log entry; the
  # wizard's wizard-chrome view also gets a transient confirmation
  # via the :last_spawn assign so the wizard knows the click worked
  # without having to flip back to the player log.
  def handle_event(
        "spawn_here",
        %{"blueprint_id" => blueprint_id},
        %{assigns: %{is_wizard: true, mode: :wizard, authoring_mode: :world}} = socket
      )
      when is_binary(blueprint_id) do
    case AgenticRealms.World.Commands.spawn_object_from_blueprint(
           socket.assigns.current_player.id,
           blueprint_id,
           socket.assigns.current_room_id
         ) do
      {:ok, object_id} ->
        bp = AgenticRealms.World.Queries.get_object_blueprint(blueprint_id)

        feedback = %{
          object_id: object_id,
          blueprint_id: blueprint_id,
          name: bp && bp.name,
          room_name: socket.assigns.current_room_name,
          at: System.monotonic_time(:millisecond)
        }

        {:noreply,
         socket
         |> assign(:blueprint_commit_error, nil)
         |> assign(:last_spawn, feedback)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:blueprint_commit_error, reason)
         |> assign(:last_spawn, nil)}
    end
  end

  def handle_event("spawn_here", _, socket), do: {:noreply, socket}

  # Feature 014 US2 — dismiss the spawn-confirmation notice. Wizard
  # explicitly closes it via the × button.
  def handle_event("dismiss_last_spawn", _, socket) do
    {:noreply, assign(socket, :last_spawn, nil)}
  end

  # While a natural-language resolver task is in flight the input is locked;
  # ignore any submit that slips through (e.g. a queued client event).
  def handle_event("submit_command", _params, %{assigns: %{input_locked: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("submit_command", %{"text" => text}, socket) do
    case CommandParser.parse(text) do
      {:empty} ->
        {:noreply, socket}

      {:look} ->
        handle_look(socket, text)

      {:look, target} ->
        handle_look_target(socket, text, target, true)

      {:inventory} ->
        handle_inventory(socket, text)

      {:move, dir} ->
        handle_move(socket, text, dir)

      {:take, name} ->
        handle_take(socket, text, name, true)

      {:drop, name} ->
        handle_drop(socket, text, name, true)

      {:invalid_take_target} ->
        echo_then_system(socket, text, "Take what?")

      {:invalid_drop_target} ->
        echo_then_system(socket, text, "Drop what?")

      {:say, said} ->
        handle_say(socket, text, said)

      {:say_empty} ->
        echo_then_system(socket, text, "Say what?")

      {:emote, said} ->
        handle_emote(socket, text, said)

      {:emote_empty} ->
        echo_then_system(socket, text, "Emote what?")

      {:tell, recipient, message} ->
        handle_tell(socket, text, recipient, message)

      {:tell_no_recipient} ->
        echo_then_system(socket, text, "Tell whom what?")

      {:tell_no_text, recipient} ->
        echo_then_system(socket, text, "Tell #{recipient} what?")

      {:whisper, recipient, message} ->
        handle_whisper(socket, text, recipient, message)

      {:whisper_no_recipient} ->
        echo_then_system(socket, text, "Whisper to whom what?")

      {:whisper_no_text, recipient} ->
        echo_then_system(socket, text, "Whisper to #{recipient} what?")

      {:chat, npc_token, message} ->
        handle_chat(socket, text, npc_token, message)

      {:chat_no_npc} ->
        echo_then_system(socket, text, "Chat with whom?")

      {:chat_no_message, npc_token} ->
        echo_then_system(socket, text, "Chat with #{npc_token} about what?")

      {:unknown, raw} ->
        handle_unknown(socket, raw)
    end
  end

  def handle_event("update_input", %{"text" => text}, socket) do
    {:noreply, assign(socket, :input, text)}
  end

  def handle_event("open_modal", %{"modal" => modal}, socket) do
    {:noreply, assign(socket, :modal, String.to_existing_atom(modal))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :modal, nil)}
  end

  def handle_event("toggle_map", _params, socket) do
    {:noreply, update(socket, :map_open, &(!&1))}
  end

  # Feature 013 — `select_quest` is unused now (the rewritten quest_modal
  # displays Active and Completed side-by-side without nav state). Kept
  # as a no-op for forward compatibility with any stale client payload.
  def handle_event("select_quest", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("set_wizard_kind", %{"kind" => kind}, socket) do
    kind_atom = String.to_existing_atom(kind)

    socket =
      socket
      |> assign(:wizard_kind, kind_atom)
      |> then(fn s ->
        if not s.assigns.wizard_user_edited do
          assign(s, :wizard_text, GameData.starter_prompts()[kind_atom] || "")
        else
          s
        end
      end)

    {:noreply, socket}
  end

  def handle_event("update_wizard_text", %{"text" => text}, socket) do
    {:noreply,
     socket
     |> assign(:wizard_text, text)
     |> assign(:wizard_user_edited, true)}
  end

  def handle_event("open_trigger", %{"id" => id}, socket) do
    example = socket.assigns.wizard_examples[socket.assigns.wizard_kind]

    trigger =
      if example do
        Enum.find(example[:triggers] || [], fn t -> t.id == id end)
      end

    {:noreply, assign(socket, :open_trigger, trigger)}
  end

  def handle_event("close_trigger", _params, socket) do
    {:noreply, assign(socket, :open_trigger, nil)}
  end

  def handle_event("stream_done", _params, socket) do
    {:noreply, assign(socket, :streaming, false)}
  end

  # --- Natural-language fallback (feature 005) -----------------------------

  # Input the fast parser couldn't resolve. Spawn a supervised async task to
  # resolve it via the LLM; lock the input and stash the task ref + raw text
  # so handle_info/2 can finish the job when the task replies.
  defp handle_unknown(socket, raw) do
    player_id = socket.assigns.current_player.id

    task =
      Task.Supervisor.async_nolink(
        AgenticRealms.IntentResolverTaskSupervisor,
        IntentResolver,
        :resolve,
        [player_id, raw]
      )

    {:noreply,
     socket
     |> assign(:resolver_task, %{ref: task.ref, raw_input: raw})
     |> assign(:input_locked, true)
     |> assign(:input, "")}
  end

  # Dispatch a resolver-produced action tuple through the same handlers the
  # fast-path parser sentinels use. `raw` is the player's literal input, so
  # the handlers echo the correct `:cmd` entry.
  defp dispatch_resolved_action(socket, raw, action) do
    case action do
      {:look} -> handle_look(socket, raw)
      {:look, target} -> handle_look_target(socket, raw, target, false)
      {:inventory} -> handle_inventory(socket, raw)
      {:move, dir} -> handle_move(socket, raw, dir)
      # allow_fallback?: false — this IS the LLM-resolved retry; a still-failing
      # take/drop refuses rather than looping back into the resolver.
      {:take, name} -> handle_take(socket, raw, name, false)
      {:drop, name} -> handle_drop(socket, raw, name, false)
      {:say, said} -> handle_say(socket, raw, said)
      {:emote, said} -> handle_emote(socket, raw, said)
      {:tell, recipient, message} -> handle_tell(socket, raw, recipient, message)
      {:whisper, recipient, message} -> handle_whisper(socket, raw, recipient, message)
      {:chat, npc_token, message} -> handle_chat(socket, raw, npc_token, message)
    end
  end

  # --- Command handlers ----------------------------------------------------

  defp handle_inventory(socket, raw) do
    player_id = socket.assigns.current_player.id
    inventory = Queries.list_inventory(player_id)

    text =
      case inventory do
        [] ->
          "You aren't carrying anything."

        items ->
          "You are carrying:\n" <>
            Enum.map_join(items, "\n", fn item ->
              "  · #{item.name} — #{item.short_description}"
            end)
      end

    {:noreply,
     socket
     |> append_log(%{kind: :cmd, text: String.trim(raw)})
     |> append_log(%{kind: :system, text: text})
     |> assign(:inventory, inventory)
     |> assign(:input, "")}
  end

  defp handle_look(socket, raw) do
    player_id = socket.assigns.current_player.id

    case Queries.look_room(player_id) do
      {:ok, room_view} ->
        {:noreply,
         socket
         |> append_log(%{kind: :cmd, text: String.trim(raw)})
         |> append_log(%{kind: :room, room: room_view})
         |> assign(:input, "")}

      {:error, _} ->
        echo_then_system(socket, raw, "You are nowhere.")
    end
  end

  # `allow_fallback?` is true on a fast-path entry: when the target name does
  # not resolve (`:no_such_target`), the raw input is handed to the LLM so it
  # can map a loose noun phrase against actual visible targets (mirror of
  # FR-001a from 005a). It is false on an LLM-dispatched retry so a
  # still-failing examine simply refuses — no fallback loop. Ambiguity
  # refusals (`:ambiguous_*`) never trigger the fallback: those are not name
  # resolution failures, they are "name resolved to too many things."
  defp handle_look_target(socket, raw, target, allow_fallback?) do
    player_id = socket.assigns.current_player.id

    case Examine.examine(player_id, target) do
      {:ok, %ExamineMatch{target_kind: :object, name: name, long_description: ld}} ->
        {:noreply,
         socket
         |> echo(raw)
         |> append_log(%{
           kind: :detail,
           target_kind: :object,
           name: name,
           long_description: ld
         })}

      {:ok, %ExamineMatch{target_kind: :player, name: name}} ->
        {:noreply,
         socket
         |> echo(raw)
         |> append_log(%{kind: :detail, target_kind: :player, name: name})}

      {:ok, %ExamineMatch{target_kind: :npc, name: name, long_description: ld}} ->
        {:noreply,
         socket
         |> echo(raw)
         |> append_log(%{
           kind: :detail,
           target_kind: :npc,
           name: name,
           long_description: ld
         })}

      {:error, :no_such_target} when allow_fallback? ->
        handle_unknown(socket, raw)

      {:error, :no_such_target} ->
        echo_then_system(socket, raw, "You don't see that here.")

      {:error, reason}
      when reason in [
             :ambiguous_in_room,
             :ambiguous_in_inventory,
             :ambiguous_mixed_kind,
             :ambiguous_player,
             :ambiguous_npc,
             :ambiguous_partial
           ] ->
        echo_then_system(socket, raw, "Which one do you mean?")

      {:error, :no_current_room} ->
        echo_then_system(socket, raw, "You are nowhere.")
    end
  end

  defp handle_move(socket, raw, dir) do
    player_id = socket.assigns.current_player.id
    from_room_id = socket.assigns.current_room_id
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")

    case Commands.move(player_id, dir) do
      {:ok, to_room_id} ->
        # Feature 009 — fire `player_left` behaviors INLINE before
        # rendering the destination room view. Otherwise the farewell
        # entries would arrive in the mailbox after handle_move returns
        # and appear visually AFTER the new room, making it feel like the
        # NPC followed the player.
        departure_entries =
          AgenticRealms.World.Behaviors.Interpreter.fire_departure_inline(
            player_id,
            from_room_id
          )

        socket = Enum.reduce(departure_entries, socket, &append_log(&2, &1))

        if connected?(socket) do
          Phoenix.PubSub.unsubscribe(
            @pubsub,
            Topics.room_topic(from_room_id)
          )

          Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(to_room_id))
        end

        case Queries.look_room(player_id) do
          {:ok, room_view} ->
            {:noreply,
             socket
             |> assign(:current_room_id, to_room_id)
             |> assign(:current_room_name, Map.get(room_view, :name))
             |> clear_room_scoped_wizard_state()
             |> refresh_map_view()
             |> refresh_room_objects()
             |> append_log(%{kind: :room, room: room_view})
             |> refresh_presence()}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:current_room_id, to_room_id)
             |> clear_room_scoped_wizard_state()
             |> refresh_map_view()
             |> refresh_room_objects()
             |> append_log(%{kind: :system, text: "You arrive somewhere."})
             |> refresh_presence()}
        end

      {:error, :no_exit_in_direction} ->
        {:noreply, append_log(socket, %{kind: :system, text: "You can't go that way."})}

      {:error, reason} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "You can't move right now (#{inspect(reason)})."
         })}
    end
  end

  # `allow_fallback?` is true on a fast-path attempt: if the object name does
  # not resolve (`:no_such_object`), the raw input is handed to the LLM, which
  # can map a loose noun phrase like "the lantern" against actual room
  # contents (feature 005a). It is false on an LLM-dispatched retry so a
  # still-failing action simply refuses — no fallback loop.
  #
  # The `:cmd` echo is deferred until after the command runs: on the fallback
  # path nothing is echoed here (the LLM-result handler echoes once when it
  # dispatches the resolved action), which keeps the log to a single echo.
  defp handle_take(socket, raw, name, allow_fallback?) do
    player_id = socket.assigns.current_player.id

    case Commands.take(player_id, name) do
      {:error, :no_such_object} when allow_fallback? ->
        handle_unknown(socket, raw)

      {:ok, %{object_name: object_name}} ->
        # Actor's own confirmation + locally refresh inventory snapshot
        # (PlayerInventoryChanged broadcast also targets us, but it'd race
        # the assign here on the originating tab — we just set inventory
        # directly).
        inventory = Queries.list_inventory(player_id)

        {:noreply,
         socket
         |> echo(raw)
         |> assign(:inventory, inventory)
         |> append_log(%{kind: :system, text: "You take the #{object_name}."})}

      {:error, err} when err in [:no_such_object, :object_not_in_room] ->
        {:noreply,
         socket |> echo(raw) |> append_log(%{kind: :system, text: "You don't see that here."})}

      {:error, :object_is_fixed} ->
        {:noreply,
         socket |> echo(raw) |> append_log(%{kind: :system, text: "You can't take that."})}

      {:error, :ambiguous} ->
        {:noreply,
         socket |> echo(raw) |> append_log(%{kind: :system, text: "Which one do you mean?"})}

      {:error, :no_current_room} ->
        {:noreply, socket |> echo(raw) |> append_log(%{kind: :system, text: "You are nowhere."})}

      {:error, reason} ->
        {:noreply,
         socket
         |> echo(raw)
         |> append_log(%{kind: :system, text: "You can't take that (#{inspect(reason)})."})}
    end
  end

  defp handle_drop(socket, raw, name, allow_fallback?) do
    player_id = socket.assigns.current_player.id

    case Commands.drop(player_id, name) do
      {:error, :not_in_inventory} when allow_fallback? ->
        handle_unknown(socket, raw)

      {:ok, %{object_name: object_name}} ->
        inventory = Queries.list_inventory(player_id)

        {:noreply,
         socket
         |> echo(raw)
         |> assign(:inventory, inventory)
         |> append_log(%{kind: :system, text: "You drop the #{object_name}."})}

      {:error, :not_in_inventory} ->
        {:noreply,
         socket |> echo(raw) |> append_log(%{kind: :system, text: "You aren't carrying that."})}

      {:error, :ambiguous} ->
        {:noreply,
         socket |> echo(raw) |> append_log(%{kind: :system, text: "Which one do you mean?"})}

      {:error, :no_current_room} ->
        {:noreply, socket |> echo(raw) |> append_log(%{kind: :system, text: "You are nowhere."})}

      {:error, reason} ->
        {:noreply,
         socket
         |> echo(raw)
         |> append_log(%{kind: :system, text: "You can't drop that (#{inspect(reason)})."})}
    end
  end

  # Append the `:cmd` echo of the player's literal input and clear the input box.
  defp echo(socket, raw) do
    socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
  end

  defp echo_then_system(socket, raw, text) do
    {:noreply,
     socket
     |> append_log(%{kind: :cmd, text: String.trim(raw)})
     |> append_log(%{kind: :system, text: text})
     |> assign(:input, "")}
  end

  # --- Communication handlers (feature 004) -------------------------------

  defp handle_say(socket, raw, said) do
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
    sender = sender_context(socket)

    case Communication.say(sender, said) do
      :ok ->
        {:noreply, append_log(socket, %{kind: :speech_self, text: said})}

      {:error, :empty} ->
        {:noreply, append_log(socket, %{kind: :system, text: "Say what?"})}

      {:error, :too_long} ->
        {:noreply, append_log(socket, %{kind: :system, text: too_long_message()})}
    end
  end

  defp handle_whisper(socket, raw, recipient, message) do
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
    sender = sender_context(socket)

    case Communication.whisper(sender, recipient, message) do
      {:ok, %{recipient_username: rname}} ->
        {:noreply,
         append_log(socket, %{
           kind: :private_whisper_out,
           recipient: rname,
           text: message
         })}

      {:error, :empty} ->
        {:noreply, append_log(socket, %{kind: :system, text: "Whisper to #{recipient} what?"})}

      {:error, :too_long} ->
        {:noreply, append_log(socket, %{kind: :system, text: too_long_message()})}

      {:error, :not_found} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "There is no one named '#{recipient}' here or anywhere."
         })}

      {:error, :ambiguous} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "Multiple players match '#{recipient}'. Use the full unique name."
         })}

      {:error, :self_target} ->
        {:noreply, append_log(socket, %{kind: :system, text: "You can't whisper to yourself."})}

      {:error, :recipient_not_in_room} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "#{recipient} is not nearby. Try `tell` instead."
         })}
    end
  end

  defp handle_tell(socket, raw, recipient, message) do
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
    sender = sender_context(socket)

    case Communication.tell(sender, recipient, message) do
      {:ok, %{recipient_username: rname}} ->
        {:noreply,
         append_log(socket, %{
           kind: :private_tell_out,
           recipient: rname,
           text: message
         })}

      {:error, :empty} ->
        {:noreply, append_log(socket, %{kind: :system, text: "Tell #{recipient} what?"})}

      {:error, :too_long} ->
        {:noreply, append_log(socket, %{kind: :system, text: too_long_message()})}

      {:error, :not_found} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "There is no one named '#{recipient}' here or anywhere."
         })}

      {:error, :ambiguous} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "Multiple players match '#{recipient}'. Use the full unique name."
         })}

      {:error, :self_target} ->
        {:noreply, append_log(socket, %{kind: :system, text: "You can't tell yourself."})}

      {:error, :not_deliverable} ->
        {:noreply,
         append_log(socket, %{kind: :system, text: "Your message could not be delivered."})}
    end
  end

  defp handle_emote(socket, raw, said) do
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
    sender = sender_context(socket)

    case Communication.emote(sender, said) do
      :ok ->
        # No separate actor-side confirmation — the actor reads the same
        # broadcast every other room subscriber gets (FR-008). The :emote_action
        # log entry is appended in handle_info/2 just like for any witness.
        {:noreply, socket}

      {:error, :empty} ->
        {:noreply, append_log(socket, %{kind: :system, text: "Emote what?"})}

      {:error, :too_long} ->
        {:noreply, append_log(socket, %{kind: :system, text: too_long_message()})}
    end
  end

  defp sender_context(socket) do
    %{
      id: socket.assigns.current_player.id,
      username: socket.assigns.current_player.username,
      session_id: socket.assigns.session_id,
      room_id: socket.assigns.current_room_id
    }
  end

  defp too_long_message, do: "Your message is too long (max 500 characters)."

  # --- NPC chat handler (feature 010) -------------------------------------
  # The chat verb routes to NPCChat.send/3 which (a) validates input,
  # (b) resolves the NPC token, (c) finds-or-starts the Conversation
  # GenServer (cluster-aware via Horde.Registry), (d) returns the
  # new-vs-continuing indicator synchronously. The reply itself arrives
  # asynchronously as a %ChatUtterance{} on the player_topic.

  defp handle_chat(socket, raw, npc_token, message) do
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
    player_id = socket.assigns.current_player.id

    case AgenticRealms.World.NPCChat.send(player_id, npc_token, message) do
      {:ok, :new} ->
        # The :chat_new system message is broadcast by the Conversation
        # itself; we just leave the input cleared and wait for it on
        # player_topic. (The reply will follow when the LLM call lands.)
        {:noreply, socket}

      {:ok, :continuing} ->
        {:noreply, socket}

      {:error, :empty_message} ->
        {:noreply, append_log(socket, %{kind: :system, text: "Chat about what?"})}

      {:error, :too_long} ->
        {:noreply, append_log(socket, %{kind: :system, text: too_long_message()})}

      {:error, :no_current_room} ->
        {:noreply, append_log(socket, %{kind: :system, text: "You are nowhere."})}

      {:error, {:no_such_npc, token}} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "You don't see #{token} here."
         })}

      {:error, {:ambiguous_npc, candidates}} ->
        names = Enum.join(candidates, ", ")

        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "There are several here. Which one — #{names}?"
         })}

      {:error, :still_thinking} ->
        # Defensive — the Conversation should broadcast its own
        # :chat_in_flight_rejection message; this is a fallback in case
        # the GenServer call path produced the error directly.
        {:noreply, socket}
    end
  end

  # --- Intent-resolver task replies (feature 005) -------------------------

  @impl true
  # The async LLM resolver finished. Demonitor (flushing the trailing :DOWN),
  # unlock the input, and either dispatch the resolved action or append the
  # refusal. `IntentResolver.resolve/2` never raises, so this is the path
  # taken for every normal completion.
  def handle_info({ref, result}, %{assigns: %{resolver_task: %{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])
    raw = socket.assigns.resolver_task.raw_input

    socket =
      socket
      |> assign(:resolver_task, nil)
      |> assign(:input_locked, false)

    case result do
      {:ok, action} ->
        dispatch_resolved_action(socket, raw, action)

      {:error, message} ->
        {:noreply,
         socket
         |> append_log(%{kind: :cmd, text: String.trim(raw)})
         |> append_log(%{kind: :system, text: message})}
    end
  end

  # Defensive: the resolver task crashed before replying (should not happen —
  # `resolve/2` rescues internally — but a task can still be killed). Surface
  # a graceful refusal rather than leaving the input locked.
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{resolver_task: %{ref: ref}}} = socket
      ) do
    raw = socket.assigns.resolver_task.raw_input

    {:noreply,
     socket
     |> assign(:resolver_task, nil)
     |> assign(:input_locked, false)
     |> append_log(%{kind: :cmd, text: String.trim(raw)})
     |> append_log(%{kind: :system, text: "I'm not sure what you meant just now."})}
  end

  # Feature 014 US1 / US3 — the wizard's authoring LLM resolver
  # finished. Outcome shape depends on the mode the task was launched
  # in: :draft_blueprint → focused_blueprint_draft (US1),
  # :freeform_object → focused_object_draft (US3). Refusals surface
  # via :blueprint_commit_error (reused for both forms).
  #
  # If the wizard switched modes between submit and completion (bug_007
  # — toggle race within the 1-3s LLM window), the draft is dropped
  # silently. Surfacing a stale draft in the other mode would surprise
  # the wizard with a forgotten prompt's output; refusing the toggle
  # would block them for the LLM call duration. Quietly discarding
  # respects both. The launching mode is stashed on the resolver task
  # at submit time so the comparison is exact.
  def handle_info(
        {ref, result},
        %{assigns: %{wizard_resolver_task: %{ref: ref} = task}} = socket
      ) do
    Process.demonitor(ref, [:flush])

    socket =
      socket
      |> assign(:wizard_resolver_task, nil)
      |> assign(:wizard_input_locked, false)

    launching_mode = Map.get(task, :mode)
    current_mode = socket.assigns.authoring_mode

    cond do
      launching_mode != nil and launching_mode != current_mode ->
        # Orphaned by a mode toggle. Drop the draft; keep input unlocked.
        {:noreply, socket}

      true ->
        apply_resolver_outcome(socket, result)
    end
  end

  # Feature 014 US1 — defensive: wizard resolver task crashed before
  # replying. Unlock the input and surface a refusal.
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{wizard_resolver_task: %{ref: ref}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:wizard_resolver_task, nil)
     |> assign(:wizard_input_locked, false)
     |> assign(:blueprint_commit_error, {:llm_refusal, "I'm not sure what you meant just now."})}
  end

  # Stale task messages (resolver_task already cleared, or a flushed :DOWN
  # raced this clause) — demonitor defensively and ignore.
  def handle_info({ref, _result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) when is_reference(ref) do
    {:noreply, socket}
  end

  # --- UI events from World.UIEventBroadcaster ----------------------------

  # First-time spawn: Phoenix.Presence's presence_diff produces the
  # "logged in" message. Discard this arrival event so witnesses don't
  # see a duplicate notification.
  def handle_info(%RoomPlayerArrived{from_direction: nil}, socket), do: {:noreply, socket}

  def handle_info(%RoomPlayerArrived{actor_id: actor_id} = msg, socket) do
    if actor_id == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> append_log(%{kind: :system, text: arrival_text(msg)})
       |> add_to_presence(actor_id, msg.actor_username)}
    end
  end

  def handle_info(%RoomPlayerLeft{actor_id: actor_id} = msg, socket) do
    if actor_id == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> append_log(%{kind: :system, text: departure_text(msg)})
       |> remove_from_presence(actor_id)}
    end
  end

  # Feature 014 — wizard trance entry/exit witness (FR-002 / FR-003 /
  # FR-004). Self-filter mirrors the FR-029 actor-exclusion pattern used
  # for player arrivals: the wizard whose toggle fired the broadcast
  # does NOT see the system entry in their own log (their chrome change
  # is the feedback they get).
  def handle_info(%RoomTranceEntered{wizard_id: wid, wizard_username: name}, socket) do
    if wid == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply, append_log(socket, %{kind: :system, text: "#{name} enters a trance."})}
    end
  end

  def handle_info(%RoomTranceExited{wizard_id: wid, wizard_username: name}, socket) do
    if wid == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply,
       append_log(socket, %{kind: :system, text: "#{name} appears to come out of a trance."})}
    end
  end

  # Feature 014 US2 — wizard-driven object arrival witness. Uses the
  # (constrained, short) `name` with an article rather than the
  # `short_description` so the entry is always a clean one-liner
  # regardless of how verbose the LLM was when extracting fields.
  # Also refreshes the wizard's :room_objects assign so the Things-in-
  # this-room panel reflects the new clone (feature 014 US4).
  def handle_info(%RoomObjectArrived{name: name}, socket) do
    {:noreply,
     socket
     |> append_log(%{kind: :system, text: object_arrival_text(name)})
     |> refresh_room_objects()}
  end

  # Feature 014 US5 — quiet in-place edit broadcast. No log entry by
  # design (wizard edits don't generate an in-fiction notification).
  # Just refresh the wizard's room-objects panel so the row reflects
  # the new values.
  def handle_info(%RoomObjectEdited{}, socket) do
    {:noreply, refresh_room_objects(socket)}
  end

  # Feature 014 US6 — live blueprint registry patching. Insert on
  # :created (after de-duping in case the same row already exists),
  # update-row on :edited. Non-wizards never subscribe so this clause
  # only fires for wizard sessions.
  def handle_info(%WizardBlueprintRegistryChanged{} = msg, socket) do
    {:noreply, patch_blueprint_registry(socket, msg)}
  end

  # NPC arrival witness (feature 007 FR-011 / FR-012 / FR-014). No actor
  # exclusion — NPCs have no acting player. Every subscriber of the room
  # topic, including every concurrent session of every player in the room,
  # receives the entry. The subsequent room view (next look or arrival)
  # re-queries Queries.look_room/1 and reflects the new NPC in the
  # "Also here" section.
  def handle_info(%RoomNPCArrived{npc_name: name}, socket) do
    {:noreply, append_log(socket, %{kind: :system, text: "#{name} arrives."})}
  end

  # Feature 009 — behavior-sourced speech. The interpreter has already
  # filtered recipients at broadcast time (`:room_speech` to triggering
  # player only; `:npc_speech` to triggering player + other room
  # occupants), so we accept every message that lands on our player-topic.
  def handle_info(%BehaviorUtterance{kind: :npc_speech} = msg, socket) do
    {:noreply,
     append_log(socket, %{
       kind: :npc_speech,
       actor_name: msg.actor_name,
       text: msg.text
     })}
  end

  def handle_info(%BehaviorUtterance{kind: :room_speech} = msg, socket) do
    {:noreply, append_log(socket, %{kind: :room_speech, text: msg.text})}
  end

  # Feature 011 — emote utterances (third-person narration).
  def handle_info(%BehaviorUtterance{kind: :room_emote} = msg, socket) do
    {:noreply, append_log(socket, %{kind: :room_emote, text: msg.text})}
  end

  def handle_info(%BehaviorUtterance{kind: :npc_emote} = msg, socket) do
    {:noreply,
     append_log(socket, %{
       kind: :npc_emote,
       actor_name: msg.actor_name,
       text: msg.text
     })}
  end

  def handle_info(%BehaviorUtterance{kind: :object_emote} = msg, socket) do
    {:noreply,
     append_log(socket, %{
       kind: :object_emote,
       actor_name: msg.actor_name,
       text: msg.text
     })}
  end

  # Feature 010 — NPC chat reply (private to the chatting player). The
  # Conversation GenServer has already filtered by player_topic so we
  # accept every message here unconditionally.
  def handle_info(%AgenticRealms.World.UIEvents.ChatUtterance{} = msg, socket) do
    {:noreply,
     append_log(socket, %{
       kind: msg.kind,
       actor_name: msg.npc_name,
       text: msg.text
     })}
  end

  def handle_info(%AgenticRealms.World.UIEvents.ChatSystemMessage{} = msg, socket) do
    {:noreply,
     append_log(socket, %{
       kind: :chat_system,
       kind_variant: msg.kind,
       text: msg.text
     })}
  end

  def handle_info(%RoomObjectTaken{actor_id: actor_id} = msg, socket) do
    socket = refresh_room_objects(socket)

    if actor_id == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply,
       append_log(socket, %{
         kind: :system,
         text: "#{msg.actor_username} takes the #{msg.object_name}."
       })}
    end
  end

  def handle_info(%RoomObjectDropped{actor_id: actor_id} = msg, socket) do
    socket = refresh_room_objects(socket)

    if actor_id == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply,
       append_log(socket, %{
         kind: :system,
         text: "#{msg.actor_username} drops the #{msg.object_name}."
       })}
    end
  end

  def handle_info(%RoomUtterance{kind: :say} = msg, socket) do
    # Actor-exclusion by session id: the speaker's originating LiveView appends
    # its own actor-side confirmation inline and discards the broadcast it
    # receives back. The speaker's OTHER sessions in the same room render the
    # broadcast as a witness entry (FR-006, multi-session pattern from 003).
    if msg.actor_session_id == socket.assigns.session_id do
      {:noreply, socket}
    else
      {:noreply, append_log(socket, %{kind: :speech, actor: msg.actor_username, text: msg.text})}
    end
  end

  def handle_info(%RoomUtterance{kind: :emote} = msg, socket) do
    # NO actor exclusion — emote includes the actor (FR-008). Every room
    # subscriber, sender included, sees the third-person narration.
    {:noreply,
     append_log(socket, %{kind: :emote_action, actor: msg.actor_username, text: msg.text})}
  end

  def handle_info(%RoomUtterance{kind: :whisper} = msg, socket) do
    # Recipient-id filter: every room subscriber receives the broadcast, but
    # only the resolved recipient renders it (FR-017). The sender's own
    # sessions also fall through this filter — their current_player.id is
    # the sender_id, not recipient_id — which gives us the FR-018 "originating
    # session only" rule for free.
    if msg.recipient_id == socket.assigns.current_player.id do
      {:noreply,
       append_log(socket, %{kind: :private_whisper_in, actor: msg.actor_username, text: msg.text})}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%PrivateUtterance{kind: :tell} = msg, socket) do
    # No filter needed — only the recipient's sessions subscribe to the
    # `player:<recipient_id>` topic (FR-011, FR-013). The sender's other
    # sessions are NOT subscribed and never receive this broadcast.
    {:noreply,
     append_log(socket, %{kind: :private_tell_in, actor: msg.actor_username, text: msg.text})}
  end

  def handle_info(%PlayerInventoryChanged{} = msg, socket) do
    # Mutate :inventory from the broadcast payload — re-querying would
    # be subject to the same :strong handler-ordering race we hit for
    # presence (Commanded doesn't order :strong handlers relative to
    # each other, so the broadcaster can fire before WorldProjector
    # commits the world_objects update). The payload carries
    # everything list_inventory would return.
    {:noreply, apply_inventory_change(socket, msg)}
  end

  # Feature 013 — Quests. Move the just-completed quest from `:quests`
  # into `:completed_quests`. The Completed section in the modal
  # surfaces it immediately. Append a system log line for the player.
  def handle_info(%PlayerQuestFinalized{} = msg, socket) do
    active = Enum.reject(socket.assigns.quests, &(&1.quest_id == msg.quest_id))

    completed_entry = %{
      quest_id: msg.quest_id,
      title: msg.title,
      reward_name: msg.reward_name,
      completed_at: msg.completed_at
    }

    completed = [completed_entry | socket.assigns.completed_quests]

    {:noreply,
     socket
     |> assign(:quests, active)
     |> assign(:completed_quests, completed)
     |> append_log(%{
       kind: :system,
       text:
         "Quest completed: #{msg.title}." <>
           if(msg.reward_name, do: " You receive #{msg.reward_name}.", else: "")
     })}
  end

  # Feature 013 — Quests. Update the matching quest's per-criterion
  # counts in place. Silent no-op if the quest isn't in our active list
  # (defensive — should not happen since broadcasts are per-player).
  def handle_info(%PlayerQuestProgress{quest_id: qid, criteria: criteria}, socket) do
    quests =
      Enum.map(socket.assigns.quests, fn
        %{quest_id: ^qid} = q -> %{q | criteria: criteria}
        other -> other
      end)

    {:noreply, assign(socket, :quests, quests)}
  end

  # Feature 013 — Quests. Append the new active quest to the HUD card
  # log. Idempotent: if a quest with this id already exists (shouldn't
  # in normal flow), we leave the list unchanged.
  def handle_info(%PlayerQuestAccepted{} = msg, socket) do
    quests = socket.assigns.quests

    if Enum.any?(quests, &(&1.quest_id == msg.quest_id)) do
      {:noreply, socket}
    else
      new_quest = %{
        quest_id: msg.quest_id,
        title: msg.title,
        narrative: msg.narrative,
        criteria: msg.criteria
      }

      {:noreply,
       socket
       |> assign(:quests, quests ++ [new_quest])
       |> append_log(%{
         kind: :system,
         text: "Quest accepted: #{msg.title}."
       })}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: payload}, socket) do
    self_id = socket.assigns.current_player.id
    my_room = socket.assigns.current_room_id

    log_entries =
      Enum.flat_map(payload.joins, fn {key, meta} ->
        presence_entries(key, meta, my_room, self_id, :login)
      end) ++
        Enum.flat_map(payload.leaves, fn {key, meta} ->
          presence_entries(key, meta, my_room, self_id, :logout)
        end)

    socket =
      Enum.reduce(log_entries, socket, fn entry, acc -> append_log(acc, entry) end)

    {:noreply, refresh_presence(socket)}
  end

  def handle_info(%PlayerCurrentRoomChanged{to_room_id: to_room_id}, socket) do
    # Our own spawn or move — the originating tab has already updated its
    # log inline (and already swapped its room subscription). For OTHER
    # tabs (multi-session, Q5), this is when we resubscribe to the new
    # room topic and re-render the room view.
    if to_room_id == socket.assigns.current_room_id do
      {:noreply, socket}
    else
      if connected?(socket) and socket.assigns.current_room_id do
        Phoenix.PubSub.unsubscribe(@pubsub, Topics.room_topic(socket.assigns.current_room_id))
      end

      if connected?(socket) do
        Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(to_room_id))
      end

      player_id = socket.assigns.current_player.id

      socket =
        socket
        |> assign(:current_room_id, to_room_id)
        |> clear_room_scoped_wizard_state()
        |> refresh_map_view()
        |> refresh_room_objects()

      case Queries.look_room(player_id) do
        {:ok, room_view} ->
          {:noreply,
           socket
           |> assign(:current_room_name, Map.get(room_view, :name))
           |> append_log(%{kind: :room, room: room_view})
           |> refresh_presence()}

        {:error, _} ->
          {:noreply, refresh_presence(socket)}
      end
    end
  end

  # nil from_direction is the first-spawn case; we discard it in handle_info
  # since Phoenix.Presence emits the "logged in" message. This clause is
  # kept defensively in case of out-of-order events.
  defp arrival_text(%RoomPlayerArrived{actor_username: name, from_direction: nil}),
    do: "#{name} logged in."

  defp arrival_text(%RoomPlayerArrived{actor_username: name, from_direction: :up}),
    do: "#{name} arrives from above."

  defp arrival_text(%RoomPlayerArrived{actor_username: name, from_direction: :down}),
    do: "#{name} arrives from below."

  defp arrival_text(%RoomPlayerArrived{actor_username: name, from_direction: dir}),
    do: "#{name} arrives from the #{Direction.to_string(dir)}."

  # Feature 014 US1 commit-create helper. Lives here in the private-
  # helper block to keep handle_event clauses grouped contiguously.
  defp commit_blueprint_create(socket, draft) do
    attrs = %{
      wizard_id: socket.assigns.current_player.id,
      blueprint_id: Map.get(draft, :proposed_slug, ""),
      name: Map.get(draft, :name, ""),
      short_description: Map.get(draft, :short_description, ""),
      long_description: Map.get(draft, :long_description, ""),
      fixed: Map.get(draft, :fixed, false)
    }

    case AgenticRealms.World.Commands.create_object_blueprint(attrs) do
      {:ok, _slug} ->
        {:noreply,
         socket
         |> assign(:focused_blueprint_draft, nil)
         |> assign(:blueprint_commit_error, nil)
         |> assign(:wizard_prompt, "")
         |> assign(:object_blueprints, Queries.list_object_blueprints())}

      {:error, reason} ->
        {:noreply, assign(socket, :blueprint_commit_error, reason)}
    end
  end

  # Feature 014 US5 commit-edit helper. Stale-revision response reloads
  # the form with the latest persisted values + surfaces a banner.
  defp commit_blueprint_edit(socket, draft, expected_revision) do
    blueprint_id = Map.get(draft, :blueprint_id) || Map.get(draft, :proposed_slug)

    fields_changed = %{
      name: Map.get(draft, :name, ""),
      short_description: Map.get(draft, :short_description, ""),
      long_description: Map.get(draft, :long_description, ""),
      fixed: Map.get(draft, :fixed, false)
    }

    case AgenticRealms.World.Commands.edit_object_blueprint(
           socket.assigns.current_player.id,
           blueprint_id,
           %{expected_revision: expected_revision, fields_changed: fields_changed}
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:focused_blueprint_draft, nil)
         |> assign(:blueprint_commit_error, nil)
         |> assign(:object_blueprints, Queries.list_object_blueprints())}

      {:error, :stale_revision, current_revision: current} ->
        bp = Queries.get_object_blueprint(blueprint_id)

        fresh_draft = %{
          blueprint_id: bp.id,
          name: bp.name,
          short_description: bp.short_description,
          long_description: bp.long_description,
          fixed: bp.fixed,
          proposed_slug: bp.id,
          expected_revision: current
        }

        {:noreply,
         socket
         |> assign(:focused_blueprint_draft, fresh_draft)
         |> assign(:blueprint_commit_error, {:stale_revision, current})}

      {:error, reason} ->
        {:noreply, assign(socket, :blueprint_commit_error, reason)}
    end
  end

  # Feature 014 US2 — wizard-driven object arrival. Normalizes the name
  # (strips any LLM-included article, lowercases) then prepends the
  # correct indefinite article. Heuristic-only — fine for "A goblin"
  # vs. "An iron lantern"; ignores edge cases like "an honor" or
  # "a unicorn" which the LLM's constrained-noun-phrase outputs are
  # vanishingly unlikely to hit.
  defp object_arrival_text(name) when is_binary(name) do
    cleaned =
      name
      |> String.trim()
      |> String.downcase()
      |> String.replace_prefix("the ", "")
      |> String.replace_prefix("an ", "")
      |> String.replace_prefix("a ", "")

    article = if String.match?(cleaned, ~r/^[aeiou]/), do: "An", else: "A"
    "#{article} #{cleaned} appears."
  end

  defp departure_text(%RoomPlayerLeft{actor_username: name, to_direction: :up}),
    do: "#{name} leaves upward."

  defp departure_text(%RoomPlayerLeft{actor_username: name, to_direction: :down}),
    do: "#{name} leaves downward."

  defp departure_text(%RoomPlayerLeft{actor_username: name, to_direction: dir}),
    do: "#{name} leaves to the #{Direction.to_string(dir)}."

  defp refresh_presence(socket) do
    presence =
      Queries.other_occupants_of(
        socket.assigns.current_room_id,
        socket.assigns.current_player.id
      )

    assign(socket, :presence, presence)
  end

  # Feature 012 — recompute the per-player MapView struct. Called every
  # time the player's current room changes (own move, other-tab swap, or
  # any future region/elevation transition). The MapView query is bounded
  # by the configured viewport (default 11×11 cells) so this stays cheap.
  #
  # FR-015 / SC-005: a region transition is just a current-room change
  # whose destination has a different `region_id`. `MapView.for_player/1`
  # reads the region from the destination room — no special-casing here.
  defp refresh_map_view(socket) do
    assign(socket, :map_view, MapView.for_player(socket.assigns.current_player.id))
  end

  # Feature 014 US4 — wizards see a Things-in-this-room panel with an
  # Extract essence button on each object. Re-query the read model on
  # any event that mutates the current room's object set.
  defp refresh_room_objects(%{assigns: %{is_wizard: true, current_room_id: rid}} = socket)
       when is_binary(rid) do
    assign(socket, :room_objects, Queries.list_objects_in_room_for_wizard(rid))
  end

  defp refresh_room_objects(socket), do: socket

  # Feature 014 US4/US5 — wizard authoring assigns that refer to a
  # specific world Object (Extract source / Edit target) are scoped to
  # the room the wizard was in when they focused. Walking into a new
  # room invalidates them — the security boundary in
  # `Commands.edit_object/3` will refuse a stale commit anyway, but
  # carrying the form into the new room is confusing UX. Clear them on
  # any move.
  defp clear_room_scoped_wizard_state(socket) do
    socket
    |> assign(:focused_object_id, nil)
    |> assign(:focused_object_draft, nil)
    |> assign(:focused_object_edit, nil)
  end

  # Feature 014 — cancelling an in-flight wizard LLM resolver task on
  # discard. Demonitors so the trailing :DOWN message is flushed; the
  # completion message that arrives later will fail to match the
  # `wizard_resolver_task: %{ref: ref}` guard and hit the generic
  # stale-task fallback. Prevents a discarded draft from re-populating
  # after the wizard thought they cancelled.
  defp cancel_wizard_resolver_task(%{assigns: %{wizard_resolver_task: %{ref: ref}}} = socket)
       when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    socket
    |> assign(:wizard_resolver_task, nil)
    |> assign(:wizard_input_locked, false)
  end

  defp cancel_wizard_resolver_task(socket), do: socket

  # Feature 014 US1 / US3 — apply the resolver-task outcome to the
  # appropriate draft assign. Helper extracted from the handle_info
  # clause so the same logic isn't repeated for the mode-matched and
  # mode-mismatched branches (the mismatched branch deliberately
  # skips this — see bug_007 in the PR #30 review).
  defp apply_resolver_outcome(socket, result) do
    case result do
      {:ok, {:draft_blueprint, fields}} ->
        slug = AgenticRealms.World.ObjectBlueprint.Slug.derive(fields.name)

        draft = %{
          name: fields.name,
          short_description: fields.short_description,
          long_description: fields.long_description,
          fixed: fields.fixed,
          proposed_slug: slug
        }

        {:noreply,
         socket
         |> assign(:focused_blueprint_draft, draft)
         |> assign(:blueprint_commit_error, nil)}

      {:ok, {:freeform_object, fields}} ->
        draft = %{
          name: fields.name,
          short_description: fields.short_description,
          long_description: fields.long_description,
          fixed: fields.fixed
        }

        {:noreply,
         socket
         |> assign(:focused_object_draft, draft)
         |> assign(:blueprint_commit_error, nil)
         |> assign(:last_spawn, nil)}

      {:error, message} ->
        {:noreply, assign(socket, :blueprint_commit_error, {:llm_refusal, message})}
    end
  end

  # Feature 014 US6 — apply a `WizardBlueprintRegistryChanged` payload
  # to the wizard's `:object_blueprints` list in place. Insert (with
  # de-dup) on :created; merge the sparse diff into the matching row
  # on :edited.
  defp patch_blueprint_registry(socket, %{
         event: :created,
         blueprint_id: bp_id,
         revision: revision,
         payload: payload
       }) do
    list = socket.assigns[:object_blueprints] || []

    if Enum.any?(list, &(&1.id == bp_id)) do
      socket
    else
      # Build a real %ObjectBlueprint{} struct so the :object_blueprints
      # assign stays homogeneous (consumers can pattern-match on the
      # struct, access timestamps, etc.). Timestamps are slightly off
      # from the projector's canonical values but within the same
      # second.
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      row = %AgenticRealms.World.Schemas.ObjectBlueprint{
        id: bp_id,
        kind: Map.get(payload, :kind, "object"),
        name: Map.get(payload, :name, ""),
        short_description: Map.get(payload, :short_description, ""),
        long_description: Map.get(payload, :long_description, ""),
        fixed: Map.get(payload, :fixed, false),
        revision: revision,
        inserted_at: now,
        updated_at: now
      }

      assign(
        socket,
        :object_blueprints,
        Enum.sort_by([row | list], &(&1.name || ""))
      )
    end
  end

  defp patch_blueprint_registry(socket, %{
         event: :edited,
         blueprint_id: bp_id,
         revision: revision,
         payload: fields_changed
       }) do
    list = socket.assigns[:object_blueprints] || []

    updated =
      Enum.map(list, fn row ->
        if row.id == bp_id do
          Enum.reduce(fields_changed, row, fn {k, v}, acc -> Map.put(acc, k, v) end)
          |> Map.put(:revision, revision)
        else
          row
        end
      end)

    assign(socket, :object_blueprints, Enum.sort_by(updated, &(&1.name || "")))
  end

  # Mutate :presence directly from the broadcast payload instead of
  # re-querying the read model. Commanded's :strong handler ordering is
  # unspecified, so the broadcaster can fire BEFORE PlayerStateProjector
  # commits — a re-query at this moment would read stale state.
  defp add_to_presence(socket, actor_id, username) do
    current = socket.assigns[:presence] || []

    if Enum.any?(current, &(&1.id == actor_id)) do
      socket
    else
      new = Enum.sort_by([%{id: actor_id, username: username} | current], & &1.username)
      assign(socket, :presence, new)
    end
  end

  defp remove_from_presence(socket, actor_id) do
    current = socket.assigns[:presence] || []
    assign(socket, :presence, Enum.reject(current, &(&1.id == actor_id)))
  end

  # Mutate :inventory from a PlayerInventoryChanged broadcast payload.
  # Same rationale as add_to_presence/3 — avoids the race against
  # WorldProjector commit ordering.
  defp apply_inventory_change(socket, %PlayerInventoryChanged{change: :added} = msg) do
    current = socket.assigns[:inventory] || []

    if Enum.any?(current, &(&1.id == msg.object_id)) do
      socket
    else
      new =
        Enum.sort_by(
          [
            %{
              id: msg.object_id,
              name: msg.object_name,
              short_description: msg.object_short_description
            }
            | current
          ],
          & &1.name
        )

      assign(socket, :inventory, new)
    end
  end

  defp apply_inventory_change(socket, %PlayerInventoryChanged{change: :removed} = msg) do
    current = socket.assigns[:inventory] || []
    assign(socket, :inventory, Enum.reject(current, &(&1.id == msg.object_id)))
  end

  defp presence_entries(key, meta, my_room, self_id, type) do
    player_id = String.to_integer(key)

    cond do
      player_id == self_id ->
        []

      true ->
        case Queries.current_room_of(player_id) do
          {:ok, ^my_room} ->
            username = presence_username(meta, player_id)
            verb = if type == :login, do: "logged in", else: "logged out"
            [%{kind: :system, text: "#{username} #{verb}."}]

          _ ->
            []
        end
    end
  end

  defp presence_username(%{metas: [%{username: u} | _]}, _player_id), do: u

  defp presence_username(_, player_id) do
    case Accounts.get_player(player_id) do
      %{username: u} -> u
      _ -> "someone"
    end
  end

  defp append_log(socket, entry), do: update(socket, :log, &(&1 ++ [entry]))

  defp build_tweaks(player) do
    %{
      theme: player.theme,
      density: player.density,
      player_layout: "classic",
      show_hud: true
    }
  end
end
