defmodule AgenticRealms.World.Behaviors.ActionExecutor do
  @moduledoc """
  Executes a single behavior action by building a transient
  `BehaviorUtterance` struct and broadcasting it on the appropriate set of
  `player_topic`s.

  Recipient sets per `contracts/ui_events.md` and FR-015:
    * `:room_speech` (room is the source) → triggering player only.
    * `:npc_speech` (NPC clone is the speaker) → triggering player + every
      other player in the speaker's room.

  Unknown / malformed actions are logged and skipped (no crash) — this
  feature ships only the `:say` action; future actions add clauses.
  """

  require Logger

  alias AgenticRealms.World
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.UIEvents.BehaviorUtterance

  @pubsub AgenticRealms.PubSub

  @typedoc """
  Speaker context — either the room itself (`{:room, room_id}`) or an NPC
  clone (`{:npc_clone, %{name: ...}}`).
  """
  @type speaker_ctx ::
          {:room, String.t()}
          | {:npc_clone, %{required(:name) => String.t(), optional(any) => any}}

  @spec execute(speaker_ctx(), map(), String.t(), integer()) :: :ok
  def execute(speaker_ctx, %{"type" => "say", "text" => text}, room_id, triggering_player_id)
      when is_binary(text) do
    utterance = build_utterance(speaker_ctx, text, room_id, triggering_player_id)
    recipients = compute_recipients(speaker_ctx, room_id, triggering_player_id)

    Enum.each(recipients, fn p_id ->
      Phoenix.PubSub.broadcast(@pubsub, World.player_topic(p_id), utterance)
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
end
