defmodule AgenticRealms.World.WizardTrance do
  @moduledoc """
  Feature 014 — wizard trance broadcast helper. Translates an
  `authoring_mode` toggle on a wizard's LiveView socket into a co-present
  player-facing log entry.

  Why this is not a Commanded aggregate / event: trance is a UI signal,
  not world state. Putting it through the event store would mean
  introducing an aggregate just to emit a transient broadcast, when
  Phoenix.PubSub already covers the live-witness path. See
  `specs/014-item-blueprints/research.md` R3.

  Subscribers (`GameLive.handle_info/2` clauses for `RoomTranceEntered`
  and `RoomTranceExited`) are responsible for actor-exclusion (FR-004
  wording: "every *other* player session"). The broadcaster fans out
  unconditionally; no Presence check is performed here, matching the
  existing `RoomPlayerArrived` / `RoomNPCArrived` broadcast pattern from
  feature 003 / 007 where subscribers filter on the receiving end.
  """

  alias AgenticRealms.World.UIEvents.{RoomTranceEntered, RoomTranceExited}
  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub

  @spec enter(integer(), String.t(), String.t()) :: :ok
  def enter(wizard_id, wizard_name, room_id)
      when is_integer(wizard_id) and is_binary(wizard_name) and is_binary(room_id) do
    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(room_id), %RoomTranceEntered{
      room_id: room_id,
      wizard_id: wizard_id,
      wizard_name: wizard_name
    })
  end

  @spec exit(integer(), String.t(), String.t()) :: :ok
  def exit(wizard_id, wizard_name, room_id)
      when is_integer(wizard_id) and is_binary(wizard_name) and is_binary(room_id) do
    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(room_id), %RoomTranceExited{
      room_id: room_id,
      wizard_id: wizard_id,
      wizard_name: wizard_name
    })
  end
end
