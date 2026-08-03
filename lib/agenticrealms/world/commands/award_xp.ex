defmodule AgenticRealms.World.Commands.AwardXp do
  @moduledoc """
  Award experience to a player (players only; NPCs never).

  `award_id` is a deterministic idempotency key (e.g. `"quest:<quest_id>"`) so
  a redelivered or replayed source event cannot double-award. `source` is a
  provenance tag for logging/telemetry.
  """
  @enforce_keys [:player_id, :amount, :award_id]
  defstruct [:player_id, :amount, :award_id, :source]
end
