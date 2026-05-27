defmodule AgenticRealms.World.Behaviors.ActionExecutor do
  @moduledoc """
  Executes a single behavior action by building a transient
  `BehaviorUtterance` struct and broadcasting it on the appropriate set of
  `player_topic`s.

  Recipient sets per `contracts/ui_events.md` and FR-015:
    * `:room_speech` (room is the source) → triggering player only when
      `triggering_player_id` is a player id (event-driven path from
      feature 009). For the tick-driven path (feature 011), where there
      is no single triggering player, pass `nil` and the action fans out
      to ALL live occupants of the room.
    * `:npc_speech` (NPC clone is the speaker) → triggering player + every
      other player in the speaker's room. For tick-driven NPC speech,
      pass `nil` — the recipient set is the same "every live occupant"
      computation, just without the explicit triggering player.
    * `:object_speech` (object is the speaker) — feature 011, fans out to
      every live occupant of the room.

  Unknown / malformed actions are logged and skipped (no crash) — this
  feature ships only the `:say` action; future actions add clauses.
  """

  require Logger

  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.UIEvents.BehaviorUtterance
  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub

  @typedoc """
  Speaker context — either the room itself (`{:room, room_id}`), an NPC
  clone (`{:npc_clone, %{name: ...}}`), or an object (`{:object,
  %{name: ...}}`, feature 011).
  """
  @type speaker_ctx ::
          {:room, String.t()}
          | {:npc_clone, %{required(:name) => String.t(), optional(any) => any}}
          | {:object, %{required(:name) => String.t(), optional(any) => any}}

  @spec execute(speaker_ctx(), map(), String.t(), integer() | nil) :: :ok
  def execute(speaker_ctx, %{"type" => "say", "text" => text}, room_id, triggering_player_id)
      when is_binary(text) do
    utterance = build_utterance(speaker_ctx, text, room_id, triggering_player_id)
    recipients = compute_recipients(speaker_ctx, room_id, triggering_player_id)

    Enum.each(recipients, fn p_id ->
      Phoenix.PubSub.broadcast(@pubsub, Topics.player_topic(p_id), utterance)
    end)

    :ok
  end

  # Feature 011 — `emote` action. Same recipient computation as `say`
  # (visibility is determined by speaker + triggering context, not by
  # action type per FR-013), but a distinct utterance kind so the
  # renderer can produce third-person narration instead of speech.
  def execute(speaker_ctx, %{"type" => "emote", "text" => text}, room_id, triggering_player_id)
      when is_binary(text) do
    utterance = build_emote_utterance(speaker_ctx, text, room_id, triggering_player_id)
    recipients = compute_recipients(speaker_ctx, room_id, triggering_player_id)

    Enum.each(recipients, fn p_id ->
      Phoenix.PubSub.broadcast(@pubsub, Topics.player_topic(p_id), utterance)
    end)

    :ok
  end

  def execute(_speaker_ctx, %{"type" => unknown} = action, _room_id, _player_id) do
    Logger.warning(
      "Behaviors.ActionExecutor: skipping unknown action type #{inspect(unknown)} (#{inspect(action)})"
    )

    :ok
  end

  def execute(_speaker_ctx, malformed, _room_id, _player_id) do
    Logger.warning("Behaviors.ActionExecutor: skipping malformed action #{inspect(malformed)}")

    :ok
  end

  defp build_utterance({:npc_clone, %{name: name}}, text, room_id, triggering_player_id) do
    %BehaviorUtterance{
      kind: :npc_speech,
      actor_name: name,
      text: text,
      room_id: room_id,
      triggering_player_id: triggering_player_id
    }
  end

  defp build_utterance({:room, _room_id}, text, room_id, triggering_player_id) do
    %BehaviorUtterance{
      kind: :room_speech,
      actor_name: nil,
      text: text,
      room_id: room_id,
      triggering_player_id: triggering_player_id
    }
  end

  defp build_utterance({:object, %{name: name}}, text, room_id, triggering_player_id) do
    %BehaviorUtterance{
      kind: :npc_speech,
      actor_name: name,
      text: text,
      room_id: room_id,
      triggering_player_id: triggering_player_id
    }
  end

  # Feature 011 — emote utterance builders. Three kinds parallel the
  # three speech kinds. Room emote has no actor_name (ambient
  # narration); NPC and object emotes carry the speaker's name so the
  # renderer can prepend it.

  defp build_emote_utterance({:room, _room_id}, text, room_id, triggering_player_id) do
    %BehaviorUtterance{
      kind: :room_emote,
      actor_name: nil,
      text: text,
      room_id: room_id,
      triggering_player_id: triggering_player_id
    }
  end

  defp build_emote_utterance({:npc_clone, %{name: name}}, text, room_id, triggering_player_id) do
    %BehaviorUtterance{
      kind: :npc_emote,
      actor_name: name,
      text: text,
      room_id: room_id,
      triggering_player_id: triggering_player_id
    }
  end

  defp build_emote_utterance({:object, %{name: name}}, text, room_id, triggering_player_id) do
    %BehaviorUtterance{
      kind: :object_emote,
      actor_name: name,
      text: text,
      room_id: room_id,
      triggering_player_id: triggering_player_id
    }
  end

  # Tick-driven path: triggering_player_id is nil. Fan out to ALL live
  # occupants of the room, regardless of speaker kind.
  defp compute_recipients(_speaker_ctx, room_id, nil) do
    Queries.live_occupants_of(room_id)
  end

  defp compute_recipients({:room, _}, _room_id, triggering_player_id) do
    [triggering_player_id]
  end

  defp compute_recipients({:npc_clone, _}, room_id, triggering_player_id) do
    other_ids =
      room_id
      |> Queries.other_occupants_of(triggering_player_id)
      |> Enum.map(& &1.id)

    [triggering_player_id | other_ids]
    |> MapSet.new()
    |> MapSet.to_list()
  end

  defp compute_recipients({:object, _}, room_id, triggering_player_id) do
    # Same fan-out as NPC speech — objects in the room speak to everyone
    # present.
    other_ids =
      room_id
      |> Queries.other_occupants_of(triggering_player_id)
      |> Enum.map(& &1.id)

    [triggering_player_id | other_ids]
    |> MapSet.new()
    |> MapSet.to_list()
  end
end
