defmodule AgenticRealms.World.NPCChat.Context do
  @moduledoc """
  Assembles the per-turn LLM request for an NPC chat (feature 010).

  `snapshot/2` queries the current room state and assembles the context
  map that `SystemPrompt.text/1` consumes — this is impure (DB-bound).

  `build_request/4` is pure: given a snapshot, the conversation history,
  the current player utterance, and the NPC name (for rendering assistant
  turns), it produces the Anthropic Messages API request body.

  See `specs/010-npc-conversations/contracts/context.md`.
  """

  alias AgenticRealms.Accounts
  alias AgenticRealms.World.NPCChat.{SystemPrompt, Tools}
  alias AgenticRealms.World.Queries

  @max_tokens 256
  @object_short_desc_limit 200

  @type snapshot :: %{
          npc_name: String.t(),
          lore: String.t(),
          room_name: String.t(),
          room_description: String.t(),
          other_players: [String.t()],
          objects: [%{name: String.t(), short_description: String.t()}],
          player_name: String.t()
        }

  @type turn ::
          %{role: :player, text: String.t()}
          | %{role: :npc, text: String.t(), mode: :speech | :emote}

  @doc """
  Build the context snapshot for the LLM call from current room state.

  Returns `{:ok, snapshot}` or `{:error, :no_current_room}` when the
  player has no resolvable room (should not happen mid-session). The
  NPC is identified by its clone struct (passed in) — we don't re-query
  it from the database.
  """
  @spec snapshot(integer(), %AgenticRealms.World.Schemas.NPCClone{}) ::
          {:ok, snapshot()} | {:error, :no_current_room}
  def snapshot(player_id, npc_clone) when is_integer(player_id) do
    with {:ok, room_view} <- Queries.look_room(player_id) do
      player = Accounts.get_player!(player_id)

      {:ok,
       %{
         npc_name: npc_clone.name,
         lore: npc_clone.lore || "",
         room_name: room_view.name,
         room_description: room_view.description,
         other_players: Enum.map(room_view.other_players, &display_name/1),
         objects: Enum.map(room_view.objects, &object_entry/1),
         player_name: player.username
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Build the Anthropic Messages API request body. Pure.
  """
  @spec build_request(snapshot(), [turn()], String.t()) :: map()
  def build_request(snapshot, turns, current_message)
      when is_list(turns) and is_binary(current_message) do
    %{
      "max_tokens" => @max_tokens,
      "system" => [
        %{
          "type" => "text",
          "text" => SystemPrompt.text(snapshot),
          "cache_control" => %{"type" => "ephemeral"}
        }
      ],
      "tools" => Tools.list(),
      "tool_choice" => %{"type" => "any"},
      "messages" =>
        message_history(turns, snapshot.npc_name) ++
          [%{"role" => "user", "content" => current_message}]
    }
  end

  # NPC turns in `turns` carry the raw text the model produced (the
  # tool_use input.text). For the API messages array we send the
  # assistant content as that raw text — wrapping it in "Garrick says,
  # '...'" or prepending the NPC name distances the model from its own
  # prior reply and degrades follow-up recall. The mode (speech vs.
  # emote) is preserved for emotes by tagging with a parenthetical
  # marker so the model can disambiguate its prior gesture from spoken
  # words; speech turns are passed through unchanged.
  defp message_history(turns, _npc_name) do
    Enum.map(turns, fn
      %{role: :player, text: text} ->
        %{"role" => "user", "content" => text}

      %{role: :npc, text: text, mode: :speech} ->
        %{"role" => "assistant", "content" => text}

      %{role: :npc, text: text, mode: :emote} ->
        %{"role" => "assistant", "content" => "(emote: #{text})"}
    end)
  end

  defp display_name(%{username: u}), do: u
  defp display_name(u) when is_binary(u), do: u

  defp object_entry(%{name: n, short_description: s}) do
    %{name: n, short_description: truncate(s, @object_short_desc_limit)}
  end

  defp truncate(nil, _), do: ""
  defp truncate(s, limit) when is_binary(s) and byte_size(s) <= limit, do: s
  defp truncate(s, limit) when is_binary(s), do: String.slice(s, 0, limit)
end
