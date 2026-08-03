defmodule AgenticRealms.World.Behaviors.Interpreter do
  @moduledoc """
  Commanded event handler that processes player-movement domain events
  (`PlayerMoved`) and fires `player_entered` behaviors in the destination
  room.

  `player_left` is NOT fired from the event handler — it would arrive in
  GameLive's mailbox AFTER the destination room view has rendered, making
  it feel like the departing NPC has somehow followed the player into the
  new room. Instead, `player_left` is fired INLINE by `GameLive.handle_move/3`
  via `fire_departure_inline/2`, BEFORE the destination room view is
  appended to the log.

  Configured with `start_from: :current` so historical events are NEVER
  replayed through this handler. Configured with
  `consistency: :strong` so the destination-room behaviors fire and
  broadcast before `Commands.move/2` returns.

  The handler produces only transient PubSub broadcasts; it does not emit
  domain events.
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    start_from: :current,
    consistency: :strong

  alias AgenticRealms.World.Behaviors.ActionExecutor
  alias AgenticRealms.World.Events.PlayerMoved
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.UIEvents.BehaviorUtterance
  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub

  @player_entered "player_entered"
  @player_left "player_left"

  def handle(
        %PlayerMoved{player_id: pid, to_room_id: to},
        _meta
      ) do
    fire_room_then_npcs(to, @player_entered, pid)
    :ok
  end

  @doc """
  Fire `player_entered` behaviors for `player_id` in `room_id`.

  Called from `GameLive`'s connected mount to deliver behavior firings on
  first-session arrival. The persistence-layer `PlayerSpawned` event fires
  during the disconnected mount (before any PubSub subscription is set up),
  so we can't reliably deliver to that mount's subscribers. Instead, the
  connected mount drives the firing AFTER subscribing to its player_topic.
  """
  @spec fire_for_arrival(integer(), String.t()) :: :ok
  def fire_for_arrival(player_id, room_id)
      when is_integer(player_id) and is_binary(room_id) do
    fire_room_then_npcs(room_id, @player_entered, player_id)
    :ok
  end

  @doc """
  Fire `player_left` behaviors for `player_id` leaving `room_id`. Called
  inline from `GameLive.handle_move/3` so the departing player sees the
  farewell BEFORE the destination room view renders (which would otherwise
  make the NPC feel like it followed the player).

  Splits delivery into two paths:

    1. Returns a list of log-entry maps for the triggering player — the
       caller (GameLive) appends them directly to its socket assigns
       before rendering the destination room.
    2. Broadcasts the same entries on `player_topic(p)` for every OTHER
       player in the source room (bystanders see the farewell via their
       async player-topic delivery — same path as `:npc_speech`).

  Returns the list of log-entry maps (possibly empty) for the triggering
  player.
  """
  @spec fire_departure_inline(integer(), String.t()) :: [map()]
  def fire_departure_inline(player_id, room_id)
      when is_integer(player_id) and is_binary(room_id) do
    inline_for_triggering_player(room_id, @player_left, player_id)
  end

  defp fire_room_then_npcs(room_id, trigger_string, triggering_player_id) do
    case Queries.get_room_behaviors(room_id) do
      {:ok, behaviors} ->
        fire_entity_behaviors(
          {:room, room_id},
          behaviors,
          trigger_string,
          room_id,
          triggering_player_id
        )

      {:error, _} ->
        :ok
    end

    clones = Queries.list_npc_clones_in_room_with_behaviors(room_id)

    Enum.each(clones, fn clone ->
      fire_entity_behaviors(
        {:npc_clone, clone},
        clone.behaviors,
        trigger_string,
        room_id,
        triggering_player_id
      )
    end)

    :ok
  end

  defp fire_entity_behaviors(_speaker_ctx, nil, _trigger, _room_id, _pid), do: :ok
  defp fire_entity_behaviors(_speaker_ctx, [], _trigger, _room_id, _pid), do: :ok

  defp fire_entity_behaviors(
         speaker_ctx,
         behaviors,
         trigger_string,
         room_id,
         triggering_player_id
       )
       when is_list(behaviors) do
    matching = matching_behaviors(behaviors, trigger_string)

    Enum.each(matching, fn behavior ->
      actions = behavior_actions(behavior)

      Enum.each(actions, fn action ->
        ActionExecutor.execute(speaker_ctx, action, room_id, triggering_player_id)
      end)
    end)
  end

  defp inline_for_triggering_player(room_id, trigger_string, triggering_player_id) do
    room_entries =
      case Queries.get_room_behaviors(room_id) do
        {:ok, behaviors} ->
          collect_entity_entries(
            {:room, room_id},
            behaviors,
            trigger_string,
            room_id,
            triggering_player_id
          )

        {:error, _} ->
          []
      end

    clones = Queries.list_npc_clones_in_room_with_behaviors(room_id)

    npc_entries =
      Enum.flat_map(clones, fn clone ->
        collect_entity_entries(
          {:npc_clone, clone},
          clone.behaviors,
          trigger_string,
          room_id,
          triggering_player_id
        )
      end)

    room_entries ++ npc_entries
  end

  defp collect_entity_entries(_speaker_ctx, nil, _trigger, _room_id, _pid), do: []
  defp collect_entity_entries(_speaker_ctx, [], _trigger, _room_id, _pid), do: []

  defp collect_entity_entries(
         speaker_ctx,
         behaviors,
         trigger_string,
         room_id,
         triggering_player_id
       )
       when is_list(behaviors) do
    matching = matching_behaviors(behaviors, trigger_string)

    Enum.flat_map(matching, fn behavior ->
      actions = behavior_actions(behavior)

      Enum.flat_map(actions, fn action ->
        entry_for_action(speaker_ctx, action, room_id, triggering_player_id)
      end)
    end)
  end

  defp entry_for_action(speaker_ctx, %{"type" => "say", "text" => text}, room_id, pid)
       when is_binary(text),
       do: do_entry_for_say(speaker_ctx, text, room_id, pid)

  defp entry_for_action(speaker_ctx, %{type: "say", text: text}, room_id, pid)
       when is_binary(text),
       do: do_entry_for_say(speaker_ctx, text, room_id, pid)

  defp entry_for_action(_speaker_ctx, _malformed, _room_id, _pid), do: []

  defp do_entry_for_say({:npc_clone, %{name: name}}, text, room_id, pid) do
    broadcast_to_others_in_room(:npc_speech, name, text, room_id, pid)
    [%{kind: :npc_speech, actor_name: name, text: text}]
  end

  defp do_entry_for_say({:room, _room_id}, text, room_id, pid) do
    _ = pid
    _ = room_id
    [%{kind: :room_speech, text: text}]
  end

  defp broadcast_to_others_in_room(kind, actor_name, text, room_id, triggering_player_id) do
    other_ids =
      room_id
      |> Queries.other_occupants_of(triggering_player_id)
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    utterance = %BehaviorUtterance{
      kind: kind,
      actor_name: actor_name,
      text: text,
      room_id: room_id,
      triggering_player_id: triggering_player_id
    }

    Enum.each(other_ids, fn p_id ->
      Phoenix.PubSub.broadcast(@pubsub, Topics.player_topic(p_id), utterance)
    end)

    :ok
  end

  defp matching_behaviors(behaviors, trigger_string) do
    Enum.filter(behaviors, fn b ->
      Map.get(b, "trigger") == trigger_string or
        Map.get(b, :trigger) == trigger_string
    end)
  end

  defp behavior_actions(behavior) do
    Map.get(behavior, "actions") || Map.get(behavior, :actions) || []
  end
end
