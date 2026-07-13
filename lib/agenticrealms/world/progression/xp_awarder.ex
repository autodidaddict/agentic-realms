defmodule AgenticRealms.World.Progression.XpAwarder do
  @moduledoc """
  Feature 019 — awards quest experience to players.

  A named `Commanded.Event.Handler` (⇒ a single exclusive cluster-wide
  subscriber, so exactly one node awards each quest's XP) that reacts to
  `QuestCompleted{xp: n}` and dispatches `AwardXp` to the Player aggregate when
  `n > 0`. Idempotency lives on the aggregate (`award_id`), so at-least-once
  redelivery/replay of `QuestCompleted` is a safe no-op. NPCs are never awarded
  experience — there is no NPC completion event (Principle I; mirrors 018's
  `NpcMinds.LifecycleManager`).
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :eventual

  alias AgenticRealms.World.Commands
  alias AgenticRealms.World.Events.QuestCompleted

  @impl true
  def handle(%QuestCompleted{player_id: pid, quest_id: qid, xp: xp}, _meta)
      when is_integer(xp) and xp > 0 do
    _ = Commands.award_xp(pid, xp, "quest:" <> qid)
    :ok
  end

  def handle(%QuestCompleted{}, _meta), do: :ok
end
