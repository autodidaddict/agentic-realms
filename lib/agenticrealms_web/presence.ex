defmodule AgenticRealmsWeb.Presence do
  @moduledoc """
  Tracks connection state for authenticated players using `Phoenix.Presence`.

  Used ONLY to drive "X logged in." / "X logged out." log entries in the
  player view. Multi-tab dedup falls out for free: Phoenix.Presence only
  emits a `joins` entry when a player's first tab connects, and a `leaves`
  entry when their last tab disconnects.

  The Here HUD card in `GameLive` is NOT driven from this — that's
  per-room world state (from `AgenticRealms.World.Queries.other_occupants_of/2`).
  A future administrative `who` command will consume this presence list.

  Topic: `"connected_players"`. Key: `to_string(player_id)`. Metadata:
  `%{name: String.t()}` — the character's name, not the account's.
  """

  use Phoenix.Presence,
    otp_app: :agenticrealms,
    pubsub_server: AgenticRealms.PubSub

  @topic "connected_players"

  @doc "PubSub topic that GameLive subscribes to and tracks against."
  def topic, do: @topic

  @doc "Track a player's session under this LiveView process."
  def track_player(pid, player_id, name) when is_integer(player_id) do
    track(pid, @topic, to_string(player_id), %{name: name})
  end
end
