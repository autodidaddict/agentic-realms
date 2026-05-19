defmodule AgenticRealmsWeb.GameLive do
  use AgenticRealmsWeb, :live_view

  import AgenticRealmsWeb.GameComponents

  alias AgenticRealms.Accounts
  alias AgenticRealms.GameData
  alias AgenticRealms.World

  alias AgenticRealms.World.{
    Commands,
    CommandParser,
    Communication,
    Direction,
    IntentResolver,
    Queries,
    Seed
  }

  alias AgenticRealms.World.UIEvents.{
    RoomPlayerArrived,
    RoomPlayerLeft,
    RoomObjectTaken,
    RoomObjectDropped,
    PlayerCurrentRoomChanged,
    PlayerInventoryChanged,
    RoomUtterance,
    PrivateUtterance
  }

  alias AgenticRealmsWeb.Presence

  @pubsub AgenticRealms.PubSub

  @impl true
  def mount(_params, _session, socket) do
    player_id = socket.assigns.current_player.id
    username = socket.assigns.current_player.username

    # `:already_spawned` is success — happens when two mounts race or when
    # the read model thinks we're not spawned (FR-022) but the aggregate
    # disagrees. The pre-dispatch check in Commands.spawn/2 returns
    # :no_current_room in both cases; the aggregate then rejects the
    # second dispatch.
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
      Phoenix.PubSub.subscribe(@pubsub, World.player_topic(player_id))
      Phoenix.PubSub.subscribe(@pubsub, World.room_topic(current_room_id))
      Phoenix.PubSub.subscribe(@pubsub, Presence.topic())
      {:ok, _} = Presence.track_player(self(), player_id, username)
    end

    {:ok,
     socket
     |> assign(:mode, :player)
     |> assign(:modal, nil)
     |> assign(:map_open, false)
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
     |> assign(:quests, GameData.quests())
     |> assign(:quest_details, GameData.quest_details())
     |> assign(:presence, presence)
     |> assign(:suggestions, GameData.suggestions())
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
    {:noreply, assign(socket, :mode, String.to_existing_atom(mode))}
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

      {:unknown, raw} ->
        handle_unknown(socket, raw)
    end
  end

  def handle_event("click_suggestion", %{"text" => text}, socket) do
    handle_event("submit_command", %{"text" => text}, socket)
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

  def handle_event("select_quest", %{"index" => index}, socket) do
    {:noreply, assign(socket, :selected_quest, String.to_integer(index))}
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

  defp handle_move(socket, raw, dir) do
    player_id = socket.assigns.current_player.id
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")

    case Commands.move(player_id, dir) do
      {:ok, to_room_id} ->
        if connected?(socket) do
          Phoenix.PubSub.unsubscribe(
            @pubsub,
            World.room_topic(socket.assigns.current_room_id)
          )

          Phoenix.PubSub.subscribe(@pubsub, World.room_topic(to_room_id))
        end

        case Queries.look_room(player_id) do
          {:ok, room_view} ->
            {:noreply,
             socket
             |> assign(:current_room_id, to_room_id)
             |> append_log(%{kind: :room, room: room_view})
             |> refresh_presence()}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:current_room_id, to_room_id)
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

  def handle_info(%RoomObjectTaken{actor_id: actor_id} = msg, socket) do
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
        Phoenix.PubSub.unsubscribe(@pubsub, World.room_topic(socket.assigns.current_room_id))
      end

      if connected?(socket) do
        Phoenix.PubSub.subscribe(@pubsub, World.room_topic(to_room_id))
      end

      player_id = socket.assigns.current_player.id

      socket = assign(socket, :current_room_id, to_room_id)

      case Queries.look_room(player_id) do
        {:ok, room_view} ->
          {:noreply, socket |> append_log(%{kind: :room, room: room_view}) |> refresh_presence()}

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

  defp arrival_text(%RoomPlayerArrived{actor_username: name, from_direction: dir}),
    do: "#{name} arrives from the #{Direction.to_string(dir)}."

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
