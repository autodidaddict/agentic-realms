defmodule AgenticRealms.World.Events.PlayerXpAwarded do
  @derive Jason.Encoder
  @enforce_keys [:player_id, :amount, :new_total, :award_id]
  defstruct [:player_id, :amount, :new_total, :award_id, version: 1]
end
