defmodule AgenticRealms.World.Communication do
  @moduledoc """
  Non-event-sourced write-side facade for player-to-player communication.

  Owns the four communication verbs introduced by feature 004 — `say`,
  `emote`, `tell`, `whisper`. None of them mutate world state, so this module
  deliberately sits OUTSIDE the Commanded write path (`World.Commands` /
  aggregates / event store) and broadcasts utterances directly on the same
  `Phoenix.PubSub` topics established for witness UI events in feature 003.

  Public contract: `specs/004-player-communication/contracts/communication_api.md`.

  All four functions accept a `sender` map sourced from a `GameLive` socket's
  assigns:

      %{id: integer(), username: binary(), session_id: reference(), room_id: binary()}

  Validation order is fixed: trim → non-empty → length cap (500 chars) →
  recipient resolution (tell/whisper) → self-target check → scope/Presence
  check → broadcast. The first refusing step short-circuits the rest.
  """

  alias AgenticRealms.World.Communication.RecipientResolver
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.UIEvents.{RoomUtterance, PrivateUtterance}
  alias AgenticRealmsWeb.Presence
  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub
  @max_length 500

  @typedoc """
  Sender context plumbed through from the calling `GameLive`. Fully populated
  on every call (no defaults; missing fields are caller errors).
  """
  @type sender :: %{
          required(:id) => integer(),
          required(:username) => binary(),
          required(:session_id) => reference(),
          required(:room_id) => binary()
        }

  # --- Public API ---------------------------------------------------------

  @doc """
  Broadcast a `say` utterance to every player in the sender's room.

  The originating session does NOT receive the broadcast back — it is excluded
  by `actor_session_id` filtering in subscribers (per FR-005). The sender's
  other sessions in the same room DO receive it as witnesses (per FR-006).

  Returns `:ok` on broadcast; `{:error, :empty}` or `{:error, :too_long}` if
  the text fails validation. The caller (GameLive) is responsible for
  appending the actor-side confirmation log entry inline.
  """
  @spec say(sender(), String.t()) :: :ok | {:error, :empty | :too_long}
  def say(%{} = sender, text) when is_binary(text) do
    with {:ok, trimmed} <- trim_and_validate(text) do
      event = %RoomUtterance{
        room_id: sender.room_id,
        actor_id: sender.id,
        actor_username: sender.username,
        actor_session_id: sender.session_id,
        kind: :say,
        text: trimmed,
        recipient_id: nil
      }

      broadcast_room(sender.room_id, event)
      :ok
    end
  end

  @doc """
  Broadcast a `whisper` — private utterance to a same-room recipient.

  The recipient MUST occupy the sender's current room. If they don't, the
  command is refused with `:recipient_not_in_room` (FR-020) — the LiveView
  surfaces a "not nearby" refusal that hints at `tell` as the cross-room
  alternative.

  Mechanically the whisper is broadcast on the SENDER'S room topic, with
  `recipient_id` set on the struct. Every room subscriber receives the
  broadcast; non-recipient subscribers (including the sender's own other
  sessions, whose `current_player.id != recipient_id`) drop it in
  `handle_info/2`. This naturally satisfies the "originating session only"
  rule for the sender (FR-018) without any session-id filter.
  """
  @spec whisper(sender(), recipient_name :: String.t(), String.t()) ::
          {:ok, %{recipient_id: integer(), recipient_username: binary()}}
          | {:error,
             :empty | :too_long | :not_found | :ambiguous | :self_target | :recipient_not_in_room}
  def whisper(%{} = sender, recipient_name, text)
      when is_binary(recipient_name) and is_binary(text) do
    with {:ok, trimmed} <- trim_and_validate(text),
         {:ok, %{id: rid, username: rname}} <-
           RecipientResolver.resolve(recipient_name, sender.id),
         :ok <- ensure_in_room(rid, sender.room_id, sender.id) do
      event = %RoomUtterance{
        room_id: sender.room_id,
        actor_id: sender.id,
        actor_username: sender.username,
        actor_session_id: sender.session_id,
        kind: :whisper,
        text: trimmed,
        recipient_id: rid
      }

      broadcast_room(sender.room_id, event)
      {:ok, %{recipient_id: rid, recipient_username: rname}}
    end
  end

  @doc """
  Send a private `tell` to a named player. Cross-room delivery is allowed:
  the message goes to every connected session of the resolved recipient
  regardless of which rooms either party occupies. Sender's other sessions
  do NOT receive a copy (the broadcast topic is the recipient's, not the
  sender's).

  Per FR-016, if the resolved recipient has zero connected sessions the
  command is refused with `:not_deliverable` — the LiveView maps this to a
  neutral "could not be delivered" refusal that does not reveal presence.
  """
  @spec tell(sender(), recipient_name :: String.t(), String.t()) ::
          {:ok, %{recipient_id: integer(), recipient_username: binary()}}
          | {:error,
             :empty | :too_long | :not_found | :ambiguous | :self_target | :not_deliverable}
  def tell(%{} = sender, recipient_name, text)
      when is_binary(recipient_name) and is_binary(text) do
    with {:ok, trimmed} <- trim_and_validate(text),
         {:ok, %{id: rid, username: rname}} <-
           RecipientResolver.resolve(recipient_name, sender.id),
         :ok <- ensure_online(rid) do
      event = %PrivateUtterance{
        actor_id: sender.id,
        actor_username: sender.username,
        recipient_id: rid,
        kind: :tell,
        text: trimmed
      }

      broadcast_private(rid, event)
      {:ok, %{recipient_id: rid, recipient_username: rname}}
    end
  end

  @doc """
  Broadcast an `emote` (third-person narration) to every player in the
  sender's room — including the actor (FR-008). A trailing period is appended
  unless the text already ends with `.`, `!`, or `?`. The actor sees the
  same broadcast every other room subscriber sees; no separate actor-side
  confirmation is generated.
  """
  @spec emote(sender(), String.t()) :: :ok | {:error, :empty | :too_long}
  def emote(%{} = sender, text) when is_binary(text) do
    with {:ok, trimmed} <- trim_and_validate(text) do
      with_punct = ensure_trailing_punctuation(trimmed)

      event = %RoomUtterance{
        room_id: sender.room_id,
        actor_id: sender.id,
        actor_username: sender.username,
        actor_session_id: sender.session_id,
        kind: :emote,
        text: with_punct,
        recipient_id: nil
      }

      broadcast_room(sender.room_id, event)
      :ok
    end
  end

  # --- Shared helpers (private) -------------------------------------------

  @doc false
  @spec trim_and_validate(String.t()) ::
          {:ok, String.t()} | {:error, :empty} | {:error, :too_long}
  def trim_and_validate(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" -> {:error, :empty}
      String.length(trimmed) > @max_length -> {:error, :too_long}
      true -> {:ok, trimmed}
    end
  end

  @doc false
  def broadcast_room(room_id, %RoomUtterance{} = event) do
    Phoenix.PubSub.broadcast(@pubsub, Topics.room_topic(room_id), event)
  end

  @doc false
  def broadcast_private(recipient_id, %PrivateUtterance{} = event) do
    Phoenix.PubSub.broadcast(@pubsub, Topics.player_topic(recipient_id), event)
  end

  @doc false
  def ensure_trailing_punctuation(text) do
    if String.match?(text, ~r/[.!?]$/), do: text, else: text <> "."
  end

  # Checks whether the resolved recipient has at least one connected session
  # tracked by `Phoenix.Presence`. Returns `:ok` if online, `{:error,
  # :not_deliverable}` if offline. FR-016.
  defp ensure_online(recipient_id) do
    case Presence.get_by_key(Presence.topic(), Integer.to_string(recipient_id)) do
      %{metas: [_ | _]} -> :ok
      _ -> {:error, :not_deliverable}
    end
  end

  # Checks whether the resolved recipient occupies the sender's current
  # room. Returns `:ok` if so, `{:error, :recipient_not_in_room}` otherwise.
  # FR-020. No Presence check is needed here — room occupancy in the read
  # model implies at least one connected session.
  defp ensure_in_room(recipient_id, room_id, sender_id) do
    if Enum.any?(Queries.other_occupants_of(room_id, sender_id), fn p -> p.id == recipient_id end) do
      :ok
    else
      {:error, :recipient_not_in_room}
    end
  end
end
