defmodule AgenticRealmsWeb.GameLive.UIEvents do
  @moduledoc """
  Handlers for the PubSub UI event payloads consumed by every
  GameLive session: room arrivals/departures, behavior utterances,
  chat replies, take/drop/say/whisper/tell witnesses, quest events,
  inventory mutations, presence diffs, and current-room changes.

  Each function takes `(socket, event)` and returns a
  `{:noreply, socket}` tuple — the matching `handle_info` clause in
  `GameLive` calls it directly.

  Also houses the arrival/departure/object-arrival text formatters
  and the presence/inventory list-mutators used by these handlers.
  Mutations work off the broadcast payload rather than re-querying
  the read model because Commanded's `:strong` handler ordering is
  unspecified — a re-query at broadcast time can read stale state.
  """

  import Phoenix.Component, only: [assign: 3]

  import AgenticRealmsWeb.GameLive.Helpers,
    only: [
      append_log: 2,
      refresh_map_view: 1,
      refresh_room_objects: 1,
      refresh_presence: 1,
      clear_room_scoped_wizard_state: 1
    ]

  alias AgenticRealms.World.PlayerNames
  alias AgenticRealms.World.{Direction, Queries, Stats}
  alias Srd.Rules.Experience

  alias AgenticRealms.World.UIEvents.{
    BehaviorUtterance,
    ChatSystemMessage,
    ChatUtterance,
    PlayerInventoryChanged,
    PlayerQuestAccepted,
    PlayerQuestFinalized,
    PlayerQuestProgress,
    PlayerStatsChanged,
    PrivateUtterance,
    RoomNPCArrived,
    RoomNPCLeft,
    RoomObjectArrived,
    RoomObjectDropped,
    RoomObjectEdited,
    RoomObjectTaken,
    RoomPlayerArrived,
    RoomPlayerLeft,
    RoomTranceEntered,
    RoomTranceExited,
    RoomUtterance,
    WizardBlueprintRegistryChanged
  }

  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub

  # ── Feature 019/020 — progression notices ─────────────────────
  #
  # Two events arrive in order: the xp gain (carries new_total) then, on
  # level-up, the level notice.
  #
  # An xp-only change moves nothing but the bar, so it is patched from the
  # broadcast payload with no database read. A *level* change moves the
  # proficiency bonus, the hitpoint maximum, the hit dice, and every proficient
  # save and skill — far more than the payload carries — so the whole sheet is
  # re-derived from the read model. That is one indexed read on a rare event.
  def stats_changed(socket, %PlayerStatsChanged{} = msg) do
    socket =
      socket
      |> refresh_stats(msg)
      |> xp_notice(msg.xp_gained)
      |> level_notice(msg.leveled_to)

    {:noreply, socket}
  end

  defp refresh_stats(socket, %PlayerStatsChanged{leveled_to: nil, new_total: nil}), do: socket

  defp refresh_stats(socket, %PlayerStatsChanged{leveled_to: nil, new_total: new_total}) do
    p = Experience.progress(new_total)

    stats =
      Map.merge(socket.assigns.stats, %{
        level: p.level,
        xp: %{
          total: new_total,
          into_level: p.into_level,
          to_next: p.to_next,
          fraction: p.fraction,
          maxed?: p.maxed?
        }
      })

    assign(socket, :stats, stats)
  end

  # A level change re-derives from the read model, but the broadcast's own
  # level and total win: progression is published by an `:eventual` handler, so
  # the projector may not have written them yet when this lands.
  defp refresh_stats(socket, %PlayerStatsChanged{} = msg) do
    overrides =
      %{}
      |> put_present(:level, msg.leveled_to)
      |> put_present(:xp, msg.new_total)

    assign(socket, :stats, Stats.for_player(socket.assigns.current_player.id, overrides))
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp xp_notice(socket, nil), do: socket

  defp xp_notice(socket, gained),
    do: append_log(socket, %{kind: :system, text: "You gain #{gained} experience."})

  defp level_notice(socket, nil), do: socket

  defp level_notice(socket, level),
    do: append_log(socket, %{kind: :system, text: "You are now level #{level}!"})

  # ────────────────────────────────────────────────────────────
  # Room player arrival / departure
  # ────────────────────────────────────────────────────────────

  def player_arrived(socket, %RoomPlayerArrived{actor_id: actor_id} = msg) do
    if actor_id == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> append_log(%{kind: :system, text: arrival_text(msg)})
       |> add_to_presence(actor_id, msg.actor_name)}
    end
  end

  def player_left(socket, %RoomPlayerLeft{actor_id: actor_id} = msg) do
    if actor_id == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> append_log(%{kind: :system, text: departure_text(msg)})
       |> remove_from_presence(actor_id)}
    end
  end

  # ────────────────────────────────────────────────────────────
  # Wizard trance witness (feature 014 FR-002 / FR-003 / FR-004)
  # ────────────────────────────────────────────────────────────

  def trance_entered(socket, %RoomTranceEntered{wizard_id: wid, wizard_name: name}) do
    if wid == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply, append_log(socket, %{kind: :system, text: "#{name} enters a trance."})}
    end
  end

  def trance_exited(socket, %RoomTranceExited{wizard_id: wid, wizard_name: name}) do
    if wid == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply,
       append_log(socket, %{kind: :system, text: "#{name} appears to come out of a trance."})}
    end
  end

  # ────────────────────────────────────────────────────────────
  # Room object events (feature 014)
  # ────────────────────────────────────────────────────────────

  @doc """
  Feature 014 US2 — wizard-driven object arrival witness. Uses the
  (constrained, short) `name` with an article rather than the
  `short_description` so the entry is always a clean one-liner
  regardless of how verbose the LLM was when extracting fields.
  Also refreshes the wizard's `:room_objects` assign so the
  Things-in-this-room panel reflects the new clone (feature 014 US4).
  """
  def object_arrived(socket, %RoomObjectArrived{name: name}) do
    {:noreply,
     socket
     |> append_log(%{kind: :system, text: object_arrival_text(name)})
     |> refresh_room_objects()}
  end

  @doc """
  Feature 014 US5 — quiet in-place edit broadcast. No log entry by
  design (wizard edits don't generate an in-fiction notification).
  Just refresh the wizard's room-objects panel so the row reflects
  the new values.
  """
  def object_edited(socket, %RoomObjectEdited{}) do
    {:noreply, refresh_room_objects(socket)}
  end

  def object_taken(socket, %RoomObjectTaken{actor_id: actor_id} = msg) do
    socket = refresh_room_objects(socket)

    if actor_id == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply,
       append_log(socket, %{
         kind: :system,
         text: "#{msg.actor_name} takes the #{msg.object_name}."
       })}
    end
  end

  def object_dropped(socket, %RoomObjectDropped{actor_id: actor_id} = msg) do
    socket = refresh_room_objects(socket)

    if actor_id == socket.assigns.current_player.id do
      {:noreply, socket}
    else
      {:noreply,
       append_log(socket, %{
         kind: :system,
         text: "#{msg.actor_name} drops the #{msg.object_name}."
       })}
    end
  end

  # ────────────────────────────────────────────────────────────
  # NPC arrival (feature 007 FR-011 / FR-012 / FR-014)
  # ────────────────────────────────────────────────────────────
  # No actor exclusion — NPCs have no acting player. Every subscriber
  # of the room topic, including every concurrent session of every
  # player in the room, receives the entry. The subsequent room view
  # re-queries Queries.look_room/1 and reflects the new NPC in the
  # "Also here" section.

  def npc_arrived(socket, %RoomNPCArrived{npc_name: name}) do
    {:noreply,
     socket
     |> append_log(%{kind: :system, text: "#{name} arrives."})
     |> refresh_room_objects()}
  end

  # Feature 018 — an NPC leaving the room (mind-driven relocation or removal),
  # mirroring npc_arrived. No actor exclusion — NPCs have no acting player.
  def npc_left(socket, %RoomNPCLeft{npc_name: name}) do
    {:noreply,
     socket
     |> append_log(%{kind: :system, text: "#{name} leaves."})
     |> refresh_room_objects()}
  end

  # ────────────────────────────────────────────────────────────
  # Behavior-sourced utterances (feature 009 / 011)
  # ────────────────────────────────────────────────────────────
  # The interpreter has already filtered recipients at broadcast time
  # (`:room_speech` to triggering player only; `:npc_speech` to
  # triggering player + other room occupants), so we accept every
  # message that lands on our player-topic.

  def behavior_utterance(socket, %BehaviorUtterance{kind: :npc_speech} = msg) do
    {:noreply,
     append_log(socket, %{
       kind: :npc_speech,
       actor_name: msg.actor_name,
       text: msg.text
     })}
  end

  def behavior_utterance(socket, %BehaviorUtterance{kind: :room_speech} = msg) do
    {:noreply, append_log(socket, %{kind: :room_speech, text: msg.text})}
  end

  def behavior_utterance(socket, %BehaviorUtterance{kind: :room_emote} = msg) do
    {:noreply, append_log(socket, %{kind: :room_emote, text: msg.text})}
  end

  def behavior_utterance(socket, %BehaviorUtterance{kind: :npc_emote} = msg) do
    {:noreply,
     append_log(socket, %{
       kind: :npc_emote,
       actor_name: msg.actor_name,
       text: msg.text
     })}
  end

  def behavior_utterance(socket, %BehaviorUtterance{kind: :object_emote} = msg) do
    {:noreply,
     append_log(socket, %{
       kind: :object_emote,
       actor_name: msg.actor_name,
       text: msg.text
     })}
  end

  # ────────────────────────────────────────────────────────────
  # NPC chat reply (feature 010) — private to the chatting player
  # ────────────────────────────────────────────────────────────
  # The Conversation GenServer has already filtered by player_topic so
  # we accept every message here unconditionally.

  def chat_utterance(socket, %ChatUtterance{} = msg) do
    {:noreply,
     append_log(socket, %{
       kind: msg.kind,
       actor_name: msg.npc_name,
       text: msg.text
     })}
  end

  def chat_system_message(socket, %ChatSystemMessage{} = msg) do
    {:noreply,
     append_log(socket, %{
       kind: :chat_system,
       kind_variant: msg.kind,
       text: msg.text
     })}
  end

  # ────────────────────────────────────────────────────────────
  # Player-driven utterances (feature 004)
  # ────────────────────────────────────────────────────────────

  @doc """
  Player-driven room utterances:

    * `:say` — actor-exclusion by session id: the speaker's
      originating LiveView appends its own actor-side confirmation
      inline and discards the broadcast it receives back. The
      speaker's OTHER sessions in the same room render the broadcast
      as a witness entry (FR-006).
    * `:emote` — NO actor exclusion (FR-008). Every room subscriber,
      sender included, sees the third-person narration.
    * `:whisper` — every room subscriber receives the broadcast, but
      only the resolved recipient renders it (FR-017). The sender's
      own sessions also fall through this filter (their
      `current_player.id` is the `sender_id`, not `recipient_id`),
      which gives us the FR-018 "originating session only" rule for
      free.
  """
  def room_utterance(socket, %RoomUtterance{kind: :say} = msg) do
    if msg.actor_session_id == socket.assigns.session_id do
      {:noreply, socket}
    else
      {:noreply, append_log(socket, %{kind: :speech, actor: msg.actor_name, text: msg.text})}
    end
  end

  def room_utterance(socket, %RoomUtterance{kind: :emote} = msg) do
    {:noreply, append_log(socket, %{kind: :emote_action, actor: msg.actor_name, text: msg.text})}
  end

  def room_utterance(socket, %RoomUtterance{kind: :whisper} = msg) do
    if msg.recipient_id == socket.assigns.current_player.id do
      {:noreply,
       append_log(socket, %{kind: :private_whisper_in, actor: msg.actor_name, text: msg.text})}
    else
      {:noreply, socket}
    end
  end

  @doc """
  `:tell` — no filter needed; only the recipient's sessions subscribe
  to the `player:<recipient_id>` topic (FR-011, FR-013). The sender's
  other sessions are NOT subscribed and never receive this broadcast.
  """
  def private_utterance(socket, %PrivateUtterance{kind: :tell} = msg) do
    {:noreply,
     append_log(socket, %{kind: :private_tell_in, actor: msg.actor_name, text: msg.text})}
  end

  # ────────────────────────────────────────────────────────────
  # Wizard blueprint registry (feature 014 US6) — delegate to Wizard
  # ────────────────────────────────────────────────────────────

  def blueprint_registry_changed(socket, %WizardBlueprintRegistryChanged{} = msg) do
    {:noreply, AgenticRealmsWeb.GameLive.Wizard.patch_blueprint_registry(socket, msg)}
  end

  # ────────────────────────────────────────────────────────────
  # Inventory mutations
  # ────────────────────────────────────────────────────────────

  def inventory_changed(socket, %PlayerInventoryChanged{} = msg) do
    # Mutate :inventory from the broadcast payload — re-querying would
    # be subject to the same :strong handler-ordering race we hit for
    # presence (Commanded doesn't order :strong handlers relative to
    # each other, so the broadcaster can fire before WorldProjector
    # commits the world_objects update). The payload carries
    # everything list_inventory would return.
    {:noreply, apply_inventory_change(socket, msg)}
  end

  # ────────────────────────────────────────────────────────────
  # Quests (feature 013)
  # ────────────────────────────────────────────────────────────

  def quest_finalized(socket, %PlayerQuestFinalized{} = msg) do
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

  def quest_progress(socket, %PlayerQuestProgress{quest_id: qid, criteria: criteria}) do
    quests =
      Enum.map(socket.assigns.quests, fn
        %{quest_id: ^qid} = q -> %{q | criteria: criteria}
        other -> other
      end)

    {:noreply, assign(socket, :quests, quests)}
  end

  def quest_accepted(socket, %PlayerQuestAccepted{} = msg) do
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

  # ────────────────────────────────────────────────────────────
  # Phoenix.Presence diffs (login / logout)
  # ────────────────────────────────────────────────────────────

  def presence_diff(socket, %Phoenix.Socket.Broadcast{event: "presence_diff", payload: payload}) do
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

  # ────────────────────────────────────────────────────────────
  # Cross-tab current-room sync
  # ────────────────────────────────────────────────────────────

  @doc """
  Our own spawn or move — the originating tab has already updated its
  log inline (and already swapped its room subscription). For OTHER
  tabs (multi-session, Q5), this is when we resubscribe to the new
  room topic and re-render the room view.
  """
  def current_room_changed(
        socket,
        %AgenticRealms.World.UIEvents.PlayerCurrentRoomChanged{to_room_id: to_room_id}
      ) do
    if to_room_id == socket.assigns.current_room_id do
      {:noreply, socket}
    else
      if Phoenix.LiveView.connected?(socket) and socket.assigns.current_room_id do
        Phoenix.PubSub.unsubscribe(@pubsub, Topics.room_topic(socket.assigns.current_room_id))
      end

      if Phoenix.LiveView.connected?(socket) do
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

  # ────────────────────────────────────────────────────────────
  # Text formatters
  # ────────────────────────────────────────────────────────────
  # nil from_direction is the first-spawn case; we discard it in the
  # caller since Phoenix.Presence emits the "logged in" message. This
  # clause is kept defensively in case of out-of-order events.

  defp arrival_text(%RoomPlayerArrived{actor_name: name, from_direction: nil}),
    do: "#{name} logged in."

  defp arrival_text(%RoomPlayerArrived{actor_name: name, from_direction: :up}),
    do: "#{name} arrives from above."

  defp arrival_text(%RoomPlayerArrived{actor_name: name, from_direction: :down}),
    do: "#{name} arrives from below."

  defp arrival_text(%RoomPlayerArrived{actor_name: name, from_direction: dir}),
    do: "#{name} arrives from the #{Direction.to_string(dir)}."

  defp departure_text(%RoomPlayerLeft{actor_name: name, to_direction: :up}),
    do: "#{name} leaves upward."

  defp departure_text(%RoomPlayerLeft{actor_name: name, to_direction: :down}),
    do: "#{name} leaves downward."

  defp departure_text(%RoomPlayerLeft{actor_name: name, to_direction: dir}),
    do: "#{name} leaves to the #{Direction.to_string(dir)}."

  # Feature 014 US2 — wizard-driven object arrival. Normalizes the
  # name (strips any LLM-included article, lowercases) then prepends
  # the correct indefinite article. Heuristic-only — fine for
  # "A goblin" vs. "An iron lantern"; ignores edge cases like
  # "an honor" or "a unicorn" which the LLM's constrained-noun-phrase
  # outputs are vanishingly unlikely to hit.
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

  # ────────────────────────────────────────────────────────────
  # Presence list mutators
  # ────────────────────────────────────────────────────────────

  defp add_to_presence(socket, actor_id, name) do
    current = socket.assigns[:presence] || []

    if Enum.any?(current, &(&1.id == actor_id)) do
      socket
    else
      new = Enum.sort_by([%{id: actor_id, name: name} | current], & &1.name)
      assign(socket, :presence, new)
    end
  end

  defp remove_from_presence(socket, actor_id) do
    current = socket.assigns[:presence] || []
    assign(socket, :presence, Enum.reject(current, &(&1.id == actor_id)))
  end

  defp presence_entries(key, meta, my_room, self_id, type) do
    player_id = String.to_integer(key)

    cond do
      player_id == self_id ->
        []

      true ->
        case Queries.current_room_of(player_id) do
          {:ok, ^my_room} ->
            name = presence_name(meta, player_id)
            verb = if type == :login, do: "logged in", else: "logged out"
            [%{kind: :system, text: "#{name} #{verb}."}]

          _ ->
            []
        end
    end
  end

  # Feature 021 — presence carries the character's name. The fallback reads it
  # from the projection rather than the account, so a stale meta cannot leak a
  # login.
  defp presence_name(%{metas: [%{name: n} | _]}, _player_id) when is_binary(n), do: n

  defp presence_name(_, player_id), do: PlayerNames.get(player_id) || "someone"

  # ────────────────────────────────────────────────────────────
  # Inventory list mutator
  # ────────────────────────────────────────────────────────────

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
end
