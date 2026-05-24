defmodule AgenticRealms.World.NPCChat do
  @moduledoc """
  Public API for NPC chat (feature 010). The top-of-tree entry point
  callers (GameLive, IntentResolver) use to initiate a chat turn.

  Responsibilities:

    1. Validate input length (FR-019a).
    2. Resolve the NPC token to a clone in the player's current room
       using the same exact-then-partial rules as `Examine` (FR-002).
    3. Find or start the `Conversation` GenServer for the
       `(player_id, npc_clone_id)` pair via the cluster-wide
       `NPCChat.Supervisor`.
    4. Forward the message via `GenServer.call`, returning the
       new-vs-continuing indicator (or an in-flight rejection).

  Side effects from the Conversation (system messages, replies) flow
  via PubSub broadcast on `World.player_topic(player_id)` — the caller
  is the LiveView, which is already subscribed.

  See `specs/010-npc-conversations/contracts/npc_chat_api.md`.
  """

  alias AgenticRealms.Repo
  alias AgenticRealms.World.NPCChat.{Registry, Supervisor}
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.NPCClone

  @max_message_length 500

  @type send_outcome ::
          {:ok, :new | :continuing}
          | {:error, :empty_message}
          | {:error, :too_long}
          | {:error, :no_current_room}
          | {:error, {:no_such_npc, String.t()}}
          | {:error, {:ambiguous_npc, [String.t()]}}
          | {:error, :still_thinking}

  @doc """
  Send a chat message from `player_id` to the NPC identified by
  `npc_token` (a player-typed name like "garrick"). Returns the
  new-vs-continuing indicator on success; the reply itself is
  broadcast asynchronously over `player_topic/1`.
  """
  @spec send(integer(), String.t(), String.t()) :: send_outcome()
  def send(player_id, npc_token, message)
      when is_integer(player_id) and is_binary(npc_token) and is_binary(message) do
    trimmed = String.trim(message)

    cond do
      trimmed == "" ->
        {:error, :empty_message}

      String.length(trimmed) > @max_message_length ->
        {:error, :too_long}

      true ->
        with {:ok, room_id} <- Queries.current_room_of(player_id),
             {:ok, clone} <- resolve_npc(room_id, npc_token),
             {:ok, pid} <- Supervisor.find_or_start(player_id, clone) do
          try do
            GenServer.call(pid, {:send, player_id, trimmed}, 5_000)
          catch
            :exit, _ -> {:error, :still_thinking}
          end
        end
    end
  end

  @doc """
  Find the Conversation pid for the pair, or return `:error` if none is
  registered. Does NOT start a new Conversation. Used by tests + debug.
  """
  @spec find(integer(), String.t()) :: {:ok, pid()} | :error
  def find(player_id, npc_clone_id) do
    Registry.lookup({player_id, npc_clone_id})
  end

  # --- NPC token resolution -------------------------------------------------

  defp resolve_npc(room_id, token) do
    needle = String.trim(token) |> String.downcase()

    clones =
      Queries.list_npcs_in_room(room_id)
      # The room-list query returns name + short_description only — fetch the
      # full clones row so we can pass `lore` into the Conversation.
      |> Enum.map(&Repo.get(NPCClone, &1.id))
      |> Enum.reject(&is_nil/1)

    exact = Enum.filter(clones, fn c -> String.downcase(c.name) == needle end)

    case exact do
      [single] ->
        {:ok, single}

      [_, _ | _] ->
        {:error, {:ambiguous_npc, Enum.map(exact, & &1.name)}}

      [] ->
        partial =
          Enum.filter(clones, fn c -> String.contains?(String.downcase(c.name), needle) end)

        case partial do
          [single] -> {:ok, single}
          [] -> {:error, {:no_such_npc, token}}
          multiple -> {:error, {:ambiguous_npc, Enum.map(multiple, & &1.name)}}
        end
    end
  end
end
