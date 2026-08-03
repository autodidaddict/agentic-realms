defmodule AgenticRealmsWeb.GameLive do
  @moduledoc """
  The main game LiveView. Routes Phoenix callbacks (`mount`,
  `handle_event`, `handle_info`) to the focused helper modules under
  `AgenticRealmsWeb.GameLive.*`:

    * `Helpers`          — small socket primitives (`append_log`,
                           `echo`, `refresh_*`, `clear_room_scoped_
                           wizard_state`)
    * `PlayerCommands`   — `look`, `inventory`, `move`, `take`,
                           `drop`, LLM-fallback resolver dispatch
    * `Communication`    — `say`, `whisper`, `tell`, `emote`, NPC
                           `chat`
    * `Wizard`           — blueprint commit pipeline, resolver
                           outcome, in-flight task cancellation,
                           registry patch
    * `UIEvents`         — PubSub event handlers (room arrivals,
                           utterances, quests, presence, inventory,
                           cross-tab room sync)

  The bodies of nearly every handle_event / handle_info clause are
  one-line delegations to a helper in one of those modules. Logic
  that doesn't fit cleanly into a helper (small wizard form updates,
  the trivial UI toggles, the command parser dispatch table) stays
  inline.
  """

  use AgenticRealmsWeb, :live_view

  use AgenticRealmsWeb.GameComponents

  alias AgenticRealms.World.{
    CharacterDraft,
    Commands,
    CommandParser,
    MapView,
    PlayerNames,
    Queries,
    Quests,
    Seed,
    Stats
  }

  alias AgenticRealms.World.UIEvents.{
    RoomPlayerArrived,
    RoomPlayerLeft,
    RoomObjectTaken,
    RoomObjectDropped,
    RoomObjectArrived,
    RoomObjectEdited,
    RoomNPCArrived,
    RoomNPCLeft,
    RoomTranceEntered,
    RoomTranceExited,
    WizardBlueprintRegistryChanged,
    BehaviorUtterance,
    PlayerCurrentRoomChanged,
    PlayerInventoryChanged,
    PlayerQuestAccepted,
    PlayerQuestProgress,
    PlayerQuestFinalized,
    PlayerStatsChanged,
    RoomUtterance,
    PrivateUtterance
  }

  alias AgenticRealmsWeb.GameLive.{
    Communication,
    Creation,
    Helpers,
    PlayerCommands,
    UIEvents,
    Wizard
  }

  alias AgenticRealmsWeb.Presence
  alias AgenticRealmsWeb.Topics

  import Helpers,
    only: [
      append_log: 2,
      echo_then_system: 3
    ]

  @pubsub AgenticRealms.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if Commands.has_character?(socket.assigns.current_player.id) do
      {:ok, enter_world(socket)}
    else
      {:ok,
       socket
       |> assign(:phase, :creating)
       |> assign(:draft, CharacterDraft.new())
       |> assign(:mode, :player)
       |> assign(:is_wizard, socket.assigns.current_player.is_wizard)
       |> assign(:tweaks, build_tweaks(socket.assigns.current_player))}
    end
  end

  defp enter_world(socket) do
    player_id = socket.assigns.current_player.id
    character_name = PlayerNames.get(player_id)

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
          raise "GameLive mount: look_room/1 returned #{inspect(reason)} for player #{player_id} after spawn — read model and aggregate are desynced"
      end

    inventory = Queries.list_inventory(player_id)
    presence = Queries.other_occupants_of(current_room_id, player_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(@pubsub, Topics.player_topic(player_id))
      Phoenix.PubSub.subscribe(@pubsub, Topics.room_topic(current_room_id))
      Phoenix.PubSub.subscribe(@pubsub, Presence.topic())

      if socket.assigns.current_player.is_wizard do
        Phoenix.PubSub.subscribe(@pubsub, Topics.blueprints_topic())
      end

      {:ok, _} = Presence.track_player(self(), player_id, character_name)

      AgenticRealms.World.Behaviors.Interpreter.fire_for_arrival(
        player_id,
        current_room_id
      )
    end

    socket
    |> assign(:phase, :playing)
    |> assign(:mode, :player)
    |> assign(:is_wizard, socket.assigns.current_player.is_wizard)
    |> assign(
      :authoring_mode,
      if(socket.assigns.current_player.is_wizard, do: :world, else: nil)
    )
    |> assign(:focused_object_id, nil)
    |> assign(:focused_blueprint_id, nil)
    |> assign(:focused_blueprint_draft, nil)
    |> assign(:focused_object_draft, nil)
    |> assign(:focused_object_edit, nil)
    |> assign(:focused_npc_edit, nil)
    |> assign(:wizard_prompt, "")
    |> assign(:wizard_resolver_task, nil)
    |> assign(:wizard_input_locked, false)
    |> assign(:blueprint_commit_error, nil)
    |> assign(:last_spawn, nil)
    |> assign(:current_room_name, Map.get(room_view, :name))
    |> assign(
      :object_blueprints,
      if(socket.assigns.current_player.is_wizard, do: Queries.list_blueprint_rows(), else: [])
    )
    |> assign(:blueprint_filter, :all)
    |> assign(
      :behavior_groups,
      if(socket.assigns.current_player.is_wizard,
        do: AgenticRealms.World.BehaviorGroups.list_for(:npc),
        else: []
      )
    )
    |> assign(
      :room_objects,
      if(socket.assigns.current_player.is_wizard,
        do: Queries.list_objects_in_room_for_wizard(current_room_id),
        else: []
      )
    )
    |> assign(
      :room_npcs,
      if(socket.assigns.current_player.is_wizard,
        do: Queries.list_npcs_in_room(current_room_id),
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
    |> assign(:session_id, make_ref())
    |> assign(:resolver_task, nil)
    |> assign(:input_locked, false)
    |> assign(:stats, Stats.for_player(player_id))
    |> assign(:inventory, inventory)
    |> assign(:quests, Quests.active_for(player_id))
    |> assign(:completed_quests, Quests.history_for(player_id))
    |> assign(:presence, presence)
    |> assign(:selected_quest, 0)
    |> assign(:tweaks, build_tweaks(socket.assigns.current_player))
  end

  @impl true
  def handle_event("creation_name", %{"value" => name}, socket) do
    {:noreply, Creation.name(socket, name)}
  end

  def handle_event("creation_select", %{"field" => field, "slug" => value}, socket)
      when field in ~w(species class background) do
    {:noreply, Creation.select(socket, String.to_existing_atom(field), presence_or_nil(value))}
  end

  def handle_event("creation_ability_up", %{"ability" => a}, socket) do
    case Creation.decode_ability(a) do
      {:ok, ability} -> {:noreply, Creation.raise_ability(socket, ability)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("creation_ability_down", %{"ability" => a}, socket) do
    case Creation.decode_ability(a) do
      {:ok, ability} -> {:noreply, Creation.lower_ability(socket, ability)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("creation_reroll", _params, socket) do
    {:noreply, Creation.reroll(socket)}
  end

  def handle_event("creation_spread", %{"spread" => spread}, socket) do
    case Creation.decode_spread(socket.assigns.draft, spread) do
      {:ok, decoded} -> {:noreply, Creation.spread(socket, decoded)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("creation_skill", %{"skill" => skill}, socket) do
    case Creation.decode_skill(socket.assigns.draft, skill) do
      {:ok, decoded} -> {:noreply, Creation.toggle_skill(socket, decoded)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("creation_pick", %{"key" => key, "option" => value}, socket) do
    case Creation.decode_pick(socket.assigns.draft, key, value) do
      {:ok, decoded_key, option} ->
        {:noreply, Creation.toggle_choice(socket, decoded_key, option)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("creation_step", %{"step" => step}, socket) do
    case Creation.decode_step(step) do
      {:ok, decoded} -> {:noreply, Creation.step(socket, decoded)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("creation_confirm", _params, socket) do
    {:noreply, Creation.confirm(socket, &enter_world/1)}
  end

  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    new_mode = String.to_existing_atom(mode)

    if new_mode == :wizard and not socket.assigns.is_wizard do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :mode, new_mode)}
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

  def handle_event("select_quest", _params, socket), do: {:noreply, socket}

  def handle_event("stream_done", _params, socket) do
    {:noreply, assign(socket, :streaming, false)}
  end

  def handle_event(
        "toggle_authoring_mode",
        _params,
        %{assigns: %{is_wizard: true, mode: :wizard}} = socket
      ) do
    wizard_id = socket.assigns.current_player.id
    wizard_name = socket.assigns.stats.name
    room_id = socket.assigns.current_room_id

    case socket.assigns.authoring_mode do
      :world ->
        :ok = AgenticRealms.World.WizardTrance.enter(wizard_id, wizard_name, room_id)

        {:noreply,
         socket
         |> assign(:authoring_mode, :blueprints)
         |> assign(:last_spawn, nil)}

      :blueprints ->
        :ok = AgenticRealms.World.WizardTrance.exit(wizard_id, wizard_name, room_id)

        {:noreply,
         socket
         |> assign(:authoring_mode, :world)
         |> assign(:focused_blueprint_id, nil)}
    end
  end

  def handle_event("toggle_authoring_mode", _params, socket), do: {:noreply, socket}

  def handle_event("update_wizard_prompt", %{"text" => text}, socket) do
    {:noreply, assign(socket, :wizard_prompt, text)}
  end

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
        AgenticRealms.World.IntentResolver,
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

  def handle_event(
        "update_blueprint_draft",
        %{"draft" => params},
        %{assigns: %{is_wizard: true, focused_blueprint_draft: draft}} = socket
      )
      when not is_nil(draft) do
    new_name = Map.get(params, "name", draft.name) || ""
    slug_input = Map.get(params, "proposed_slug", "") || ""

    proposed_slug =
      if slug_input == "" do
        AgenticRealms.World.Blueprint.Slug.derive(new_name)
      else
        slug_input
      end

    updated =
      draft
      |> Map.put(:name, new_name)
      |> Map.put(
        :short_description,
        Map.get(params, "short_description", draft.short_description) || ""
      )
      |> Map.put(
        :long_description,
        Map.get(params, "long_description", draft.long_description) || ""
      )
      |> Map.put(:fixed, Map.get(params, "fixed") == "true")
      |> Map.put(:proposed_slug, proposed_slug)
      |> put_npc_draft_fields(params)

    {:noreply,
     socket
     |> assign(:focused_blueprint_draft, updated)
     |> assign(:blueprint_commit_error, nil)}
  end

  def handle_event("update_blueprint_draft", _, socket), do: {:noreply, socket}

  def handle_event(
        "add_direct_behavior",
        _params,
        %{assigns: %{is_wizard: true, focused_blueprint_draft: draft}} = socket
      )
      when not is_nil(draft) do
    blank = %{"trigger" => "player_entered", "actions" => [%{"type" => "say", "text" => ""}]}
    behaviors = (Map.get(draft, :behaviors) || []) ++ [blank]
    {:noreply, assign(socket, :focused_blueprint_draft, Map.put(draft, :behaviors, behaviors))}
  end

  def handle_event("add_direct_behavior", _, socket), do: {:noreply, socket}

  def handle_event(
        "remove_direct_behavior",
        %{"index" => index},
        %{assigns: %{is_wizard: true, focused_blueprint_draft: draft}} = socket
      )
      when not is_nil(draft) do
    behaviors =
      case Integer.parse(index) do
        {i, _} -> (Map.get(draft, :behaviors) || []) |> List.delete_at(i)
        :error -> Map.get(draft, :behaviors) || []
      end

    {:noreply, assign(socket, :focused_blueprint_draft, Map.put(draft, :behaviors, behaviors))}
  end

  def handle_event("remove_direct_behavior", _, socket), do: {:noreply, socket}

  def handle_event(
        "commit_blueprint_draft",
        _params,
        %{assigns: %{is_wizard: true, focused_blueprint_draft: draft}} = socket
      )
      when not is_nil(draft) do
    case Map.get(draft, :expected_revision) do
      nil -> Wizard.commit_blueprint_create(socket, draft)
      revision when is_integer(revision) -> Wizard.commit_blueprint_edit(socket, draft, revision)
    end
  end

  def handle_event("commit_blueprint_draft", _, socket), do: {:noreply, socket}

  def handle_event(
        "focus_blueprint",
        %{"blueprint_id" => blueprint_id},
        %{assigns: %{is_wizard: true, mode: :wizard}} = socket
      )
      when is_binary(blueprint_id) do
    case Queries.get_blueprint(blueprint_id) do
      nil ->
        {:noreply, assign(socket, :blueprint_commit_error, :unknown_blueprint)}

      bp ->
        draft = %{
          blueprint_id: bp.id,
          kind: bp.kind,
          name: bp.name,
          short_description: bp.short_description,
          long_description: bp.long_description,
          fixed: bp.fixed,
          lore: bp.lore || "",
          behaviors: bp.behaviors || [],
          behavior_groups: bp.behavior_groups || [],
          proposed_slug: bp.id,
          expected_revision: bp.revision
        }

        socket =
          if socket.assigns.authoring_mode == :world do
            :ok =
              AgenticRealms.World.WizardTrance.enter(
                socket.assigns.current_player.id,
                socket.assigns.stats.name,
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

  def handle_event(
        "filter_blueprints",
        %{"kind" => kind},
        %{assigns: %{is_wizard: true}} = socket
      ) do
    filter =
      case kind do
        "object" -> :object
        "npc" -> :npc
        _ -> :all
      end

    {:noreply, assign(socket, :blueprint_filter, filter)}
  end

  def handle_event("filter_blueprints", _, socket), do: {:noreply, socket}

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
    case Queries.get_object_for_wizard(object_id) do
      nil ->
        {:noreply, assign(socket, :blueprint_commit_error, :unknown_object)}

      %{container_type: "room", container_id: ^room_id} = obj ->
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

    case Commands.edit_object(
           socket.assigns.current_player.id,
           edit.object_id,
           fields_changed
         ) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:focused_object_edit, nil)
         |> assign(:blueprint_commit_error, nil)
         |> Helpers.refresh_room_objects()}

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

  def handle_event(
        "focus_npc_for_edit",
        %{"clone_id" => clone_id},
        %{
          assigns: %{
            is_wizard: true,
            mode: :wizard,
            authoring_mode: :world,
            current_room_id: room_id
          }
        } = socket
      )
      when is_binary(clone_id) do
    case Queries.get_npc_clone_row(clone_id) do
      %{room_id: ^room_id} = clone ->
        edit = %{
          clone_id: clone.id,
          name: clone.name || "",
          short_description: clone.short_description || "",
          long_description: clone.long_description || "",
          lore: clone.lore || "",
          fixed: clone.fixed == true
        }

        {:noreply,
         socket
         |> assign(:focused_npc_edit, edit)
         |> assign(:focused_object_edit, nil)
         |> assign(:focused_object_draft, nil)
         |> assign(:blueprint_commit_error, nil)}

      _ ->
        {:noreply, assign(socket, :blueprint_commit_error, :unknown_npc)}
    end
  end

  def handle_event("focus_npc_for_edit", _, socket), do: {:noreply, socket}

  def handle_event(
        "update_npc_edit",
        %{"edit" => params},
        %{assigns: %{is_wizard: true, focused_npc_edit: edit}} = socket
      )
      when not is_nil(edit) do
    updated = %{
      clone_id: edit.clone_id,
      name: Map.get(params, "name", edit.name) || "",
      short_description: Map.get(params, "short_description", edit.short_description) || "",
      long_description: Map.get(params, "long_description", edit.long_description) || "",
      lore: Map.get(params, "lore", edit.lore) || "",
      fixed: Map.get(params, "fixed") == "true"
    }

    {:noreply,
     socket
     |> assign(:focused_npc_edit, updated)
     |> assign(:blueprint_commit_error, nil)}
  end

  def handle_event("update_npc_edit", _, socket), do: {:noreply, socket}

  def handle_event(
        "commit_npc_edit",
        _params,
        %{
          assigns: %{
            is_wizard: true,
            mode: :wizard,
            authoring_mode: :world,
            focused_npc_edit: edit
          }
        } = socket
      )
      when not is_nil(edit) do
    fields_changed = %{
      name: edit.name,
      short_description: edit.short_description,
      long_description: edit.long_description,
      lore: edit.lore,
      fixed: edit.fixed
    }

    case Commands.edit_npc(socket.assigns.current_player.id, edit.clone_id, fields_changed) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:focused_npc_edit, nil)
         |> assign(:blueprint_commit_error, nil)
         |> Helpers.refresh_room_objects()}

      {:error, reason} ->
        {:noreply, assign(socket, :blueprint_commit_error, reason)}
    end
  end

  def handle_event("commit_npc_edit", _, socket), do: {:noreply, socket}

  def handle_event("discard_npc_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:focused_npc_edit, nil)
     |> assign(:blueprint_commit_error, nil)}
  end

  def handle_event("discard_blueprint_draft", _, socket) do
    {:noreply,
     socket
     |> Wizard.cancel_resolver_task()
     |> assign(:focused_blueprint_draft, nil)
     |> assign(:blueprint_commit_error, nil)}
  end

  def handle_event(
        "update_object_draft",
        %{"draft" => params},
        %{assigns: %{is_wizard: true, focused_object_draft: draft}} = socket
      )
      when not is_nil(draft) do
    updated =
      draft
      |> Map.put(:name, Map.get(params, "name", draft.name) || "")
      |> Map.put(
        :short_description,
        Map.get(params, "short_description", draft.short_description) || ""
      )
      |> Map.put(
        :long_description,
        Map.get(params, "long_description", draft.long_description) || ""
      )
      |> Map.put(:fixed, Map.get(params, "fixed") == "true")

    updated =
      if Map.get(draft, :kind) == "npc" do
        Map.put(updated, :lore, Map.get(params, "lore", Map.get(draft, :lore, "")) || "")
      else
        updated
      end

    {:noreply,
     socket
     |> assign(:focused_object_draft, updated)
     |> assign(:blueprint_commit_error, nil)}
  end

  def handle_event("update_object_draft", _, socket), do: {:noreply, socket}

  def handle_event(
        "commit_object_draft",
        _params,
        %{
          assigns: %{
            is_wizard: true,
            mode: :wizard,
            authoring_mode: :world,
            focused_object_draft: draft
          }
        } = socket
      )
      when not is_nil(draft) do
    attrs = %{
      name: Map.get(draft, :name, ""),
      short_description: Map.get(draft, :short_description, ""),
      long_description: Map.get(draft, :long_description, ""),
      fixed: Map.get(draft, :fixed, false),
      lore: Map.get(draft, :lore, "")
    }

    player_id = socket.assigns.current_player.id
    room_id = socket.assigns.current_room_id

    spawn_result =
      case Map.get(draft, :kind) do
        "npc" -> Commands.spawn_npc_freeform(player_id, room_id, attrs)
        _ -> Commands.spawn_object_freeform(player_id, room_id, attrs)
      end

    case spawn_result do
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

  def handle_event("discard_object_draft", _, socket) do
    {:noreply,
     socket
     |> Wizard.cancel_resolver_task()
     |> assign(:focused_object_draft, nil)
     |> assign(:blueprint_commit_error, nil)}
  end

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
    case Queries.get_object_for_wizard(object_id) do
      nil ->
        {:noreply, assign(socket, :blueprint_commit_error, :unknown_object)}

      %{container_type: "room", container_id: ^room_id} = object ->
        slug = AgenticRealms.World.Blueprint.Slug.derive(object.name || "")

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
            socket.assigns.stats.name,
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
        {:noreply, assign(socket, :blueprint_commit_error, :object_not_in_room)}
    end
  end

  def handle_event("extract_essence", _, socket), do: {:noreply, socket}

  def handle_event(
        "extract_npc_essence",
        %{"clone_id" => clone_id},
        %{
          assigns: %{
            is_wizard: true,
            mode: :wizard,
            authoring_mode: :world,
            current_room_id: room_id
          }
        } = socket
      )
      when is_binary(clone_id) do
    case Queries.get_npc_clone_row(clone_id) do
      nil ->
        {:noreply, assign(socket, :blueprint_commit_error, :unknown_npc)}

      %{room_id: ^room_id} = clone ->
        draft = %{
          kind: "npc",
          name: clone.name || "",
          short_description: clone.short_description || "",
          long_description: clone.long_description || "",
          fixed: clone.fixed == true,
          lore: clone.lore || "",
          behaviors: clone.direct_behaviors || [],
          behavior_groups: clone.behavior_groups || [],
          proposed_slug: AgenticRealms.World.Blueprint.Slug.derive(clone.name || "")
        }

        :ok =
          AgenticRealms.World.WizardTrance.enter(
            socket.assigns.current_player.id,
            socket.assigns.stats.name,
            room_id
          )

        {:noreply,
         socket
         |> assign(:authoring_mode, :blueprints)
         |> assign(:focused_blueprint_draft, draft)
         |> assign(:focused_object_draft, nil)
         |> assign(:focused_object_edit, nil)
         |> assign(:blueprint_commit_error, nil)
         |> assign(:last_spawn, nil)}

      _other_room ->
        {:noreply, assign(socket, :blueprint_commit_error, :unknown_npc)}
    end
  end

  def handle_event("extract_npc_essence", _, socket), do: {:noreply, socket}

  def handle_event(
        "spawn_here",
        %{"blueprint_id" => blueprint_id},
        %{assigns: %{is_wizard: true, mode: :wizard, authoring_mode: :world}} = socket
      )
      when is_binary(blueprint_id) do
    case Commands.spawn_from_blueprint(
           socket.assigns.current_player.id,
           blueprint_id,
           socket.assigns.current_room_id
         ) do
      {:ok, entity_id} ->
        bp = Queries.get_blueprint(blueprint_id)

        feedback = %{
          object_id: entity_id,
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

  def handle_event("dismiss_last_spawn", _, socket) do
    {:noreply, assign(socket, :last_spawn, nil)}
  end

  def handle_event("submit_command", _params, %{assigns: %{input_locked: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("submit_command", %{"text" => text}, socket) do
    case CommandParser.parse(text) do
      {:empty} -> {:noreply, socket}
      {:look} -> PlayerCommands.look(socket, text)
      {:look, target} -> PlayerCommands.look_target(socket, text, target, true)
      {:inventory} -> PlayerCommands.inventory(socket, text)
      {:move, dir} -> PlayerCommands.move(socket, text, dir)
      {:take, name} -> PlayerCommands.take(socket, text, name, true)
      {:drop, name} -> PlayerCommands.drop(socket, text, name, true)
      {:invalid_take_target} -> echo_then_system(socket, text, "Take what?")
      {:invalid_drop_target} -> echo_then_system(socket, text, "Drop what?")
      {:say, said} -> Communication.say(socket, text, said)
      {:say_empty} -> echo_then_system(socket, text, "Say what?")
      {:emote, said} -> Communication.emote(socket, text, said)
      {:emote_empty} -> echo_then_system(socket, text, "Emote what?")
      {:tell, recipient, message} -> Communication.tell(socket, text, recipient, message)
      {:tell_no_recipient} -> echo_then_system(socket, text, "Tell whom what?")
      {:tell_no_text, r} -> echo_then_system(socket, text, "Tell #{r} what?")
      {:whisper, recipient, message} -> Communication.whisper(socket, text, recipient, message)
      {:whisper_no_recipient} -> echo_then_system(socket, text, "Whisper to whom what?")
      {:whisper_no_text, r} -> echo_then_system(socket, text, "Whisper to #{r} what?")
      {:chat, npc_token, message} -> Communication.chat(socket, text, npc_token, message)
      {:chat_no_npc} -> echo_then_system(socket, text, "Chat with whom?")
      {:chat_no_message, t} -> echo_then_system(socket, text, "Chat with #{t} about what?")
      {:unknown, raw} -> PlayerCommands.unknown(socket, raw)
    end
  end

  @impl true
  def handle_info({ref, result}, %{assigns: %{resolver_task: %{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])
    raw = socket.assigns.resolver_task.raw_input

    socket =
      socket
      |> assign(:resolver_task, nil)
      |> assign(:input_locked, false)

    case result do
      {:ok, action} ->
        PlayerCommands.dispatch_resolved_action(socket, raw, action)

      {:error, message} ->
        {:noreply,
         socket
         |> append_log(%{kind: :cmd, text: String.trim(raw)})
         |> append_log(%{kind: :system, text: message})}
    end
  end

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

    if launching_mode != nil and launching_mode != current_mode do
      {:noreply, socket}
    else
      Wizard.apply_resolver_outcome(socket, result)
    end
  end

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

  def handle_info({ref, _result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) when is_reference(ref) do
    {:noreply, socket}
  end

  def handle_info(%RoomPlayerArrived{from_direction: nil}, socket), do: {:noreply, socket}

  def handle_info(%RoomPlayerArrived{} = msg, socket), do: UIEvents.player_arrived(socket, msg)
  def handle_info(%RoomPlayerLeft{} = msg, socket), do: UIEvents.player_left(socket, msg)

  def handle_info(:transient_region_ended, socket) do
    {:noreply,
     append_log(socket, %{
       kind: :system,
       text:
         "The rift collapses — the transient region has ended. You have been returned to where you came from."
     })}
  end

  def handle_info(%RoomTranceEntered{} = msg, socket), do: UIEvents.trance_entered(socket, msg)
  def handle_info(%RoomTranceExited{} = msg, socket), do: UIEvents.trance_exited(socket, msg)
  def handle_info(%RoomObjectArrived{} = msg, socket), do: UIEvents.object_arrived(socket, msg)
  def handle_info(%RoomObjectEdited{} = msg, socket), do: UIEvents.object_edited(socket, msg)
  def handle_info(%RoomObjectTaken{} = msg, socket), do: UIEvents.object_taken(socket, msg)
  def handle_info(%RoomObjectDropped{} = msg, socket), do: UIEvents.object_dropped(socket, msg)
  def handle_info(%RoomNPCArrived{} = msg, socket), do: UIEvents.npc_arrived(socket, msg)
  def handle_info(%RoomNPCLeft{} = msg, socket), do: UIEvents.npc_left(socket, msg)

  def handle_info(%BehaviorUtterance{} = msg, socket),
    do: UIEvents.behavior_utterance(socket, msg)

  def handle_info(%RoomUtterance{} = msg, socket), do: UIEvents.room_utterance(socket, msg)
  def handle_info(%PrivateUtterance{} = msg, socket), do: UIEvents.private_utterance(socket, msg)

  def handle_info(%WizardBlueprintRegistryChanged{} = msg, socket),
    do: UIEvents.blueprint_registry_changed(socket, msg)

  def handle_info(%AgenticRealms.World.UIEvents.ChatUtterance{} = msg, socket),
    do: UIEvents.chat_utterance(socket, msg)

  def handle_info(%AgenticRealms.World.UIEvents.ChatSystemMessage{} = msg, socket),
    do: UIEvents.chat_system_message(socket, msg)

  def handle_info(%PlayerInventoryChanged{} = msg, socket),
    do: UIEvents.inventory_changed(socket, msg)

  def handle_info(%PlayerQuestFinalized{} = msg, socket),
    do: UIEvents.quest_finalized(socket, msg)

  def handle_info(%PlayerQuestProgress{} = msg, socket),
    do: UIEvents.quest_progress(socket, msg)

  def handle_info(%PlayerQuestAccepted{} = msg, socket),
    do: UIEvents.quest_accepted(socket, msg)

  def handle_info(%PlayerStatsChanged{} = msg, socket),
    do: UIEvents.stats_changed(socket, msg)

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"} = msg, socket),
    do: UIEvents.presence_diff(socket, msg)

  def handle_info(%PlayerCurrentRoomChanged{} = msg, socket),
    do: UIEvents.current_room_changed(socket, msg)

  defp presence_or_nil(""), do: nil
  defp presence_or_nil(value), do: value

  defp build_tweaks(player) do
    %{
      theme: player.theme,
      density: player.density,
      player_layout: "classic",
      show_hud: true
    }
  end

  defp put_npc_draft_fields(%{kind: "npc"} = draft, params) do
    draft
    |> Map.put(:lore, Map.get(params, "lore", Map.get(draft, :lore, "")) || "")
    |> Map.put(:behavior_groups, params |> Map.get("behavior_groups", []) |> List.wrap())
    |> Map.put(:behaviors, parse_direct_behaviors(params, draft))
  end

  defp put_npc_draft_fields(draft, _params), do: draft

  defp parse_direct_behaviors(%{"behaviors" => rows}, _draft) when is_map(rows) do
    rows
    |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)
    |> Enum.map(fn {_k, row} ->
      %{
        "trigger" => Map.get(row, "trigger", "player_entered"),
        "actions" => [
          %{"type" => Map.get(row, "type", "say"), "text" => Map.get(row, "text", "")}
        ]
      }
    end)
  end

  defp parse_direct_behaviors(_params, draft), do: Map.get(draft, :behaviors, []) || []
end
