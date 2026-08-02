defmodule AgenticRealmsWeb.GameLive.Communication do
  @moduledoc """
  Communication verb handlers (feature 004 + feature 010 NPC chat) —
  `say`, `whisper`, `tell`, `emote`, `chat`. Same shape as the player
  command handlers: take socket + raw input + verb-specific args,
  return `{:noreply, socket}`.

  The actor's own session pattern is verb-dependent:

    * `:say` → actor-side `:speech_self` entry rendered inline; the
      witness broadcast it produces is self-filtered downstream.
    * `:emote` → no inline entry; the actor renders the same
      `:emote_action` broadcast every witness sees (FR-008).
    * `:tell` / `:whisper` → actor-side outgoing entry rendered inline;
      the incoming broadcast renders for recipients only.
    * `:chat` → no inline entry; the conversation GenServer broadcasts
      the system message and the eventual reply.
  """

  import Phoenix.Component, only: [assign: 3]

  import AgenticRealmsWeb.GameLive.Helpers, only: [append_log: 2]

  alias AgenticRealms.World.Communication

  def say(socket, raw, said) do
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
    sender = sender_context(socket)

    case Communication.say(sender, said) do
      :ok ->
        {:noreply, append_log(socket, %{kind: :speech_self, text: said})}

      {:error, :empty} ->
        {:noreply, append_log(socket, %{kind: :system, text: "Say what?"})}

      {:error, :too_long} ->
        {:noreply, append_log(socket, %{kind: :system, text: too_long_message()})}
    end
  end

  def whisper(socket, raw, recipient, message) do
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
    sender = sender_context(socket)

    case Communication.whisper(sender, recipient, message) do
      {:ok, %{recipient_name: rname}} ->
        {:noreply,
         append_log(socket, %{
           kind: :private_whisper_out,
           recipient: rname,
           text: message
         })}

      {:error, :empty} ->
        {:noreply, append_log(socket, %{kind: :system, text: "Whisper to #{recipient} what?"})}

      {:error, :too_long} ->
        {:noreply, append_log(socket, %{kind: :system, text: too_long_message()})}

      {:error, :not_found} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "There is no one named '#{recipient}' here or anywhere."
         })}

      {:error, :ambiguous} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "Multiple players match '#{recipient}'. Use the full unique name."
         })}

      {:error, :self_target} ->
        {:noreply, append_log(socket, %{kind: :system, text: "You can't whisper to yourself."})}

      {:error, :recipient_not_in_room} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "#{recipient} is not nearby. Try `tell` instead."
         })}
    end
  end

  def tell(socket, raw, recipient, message) do
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
    sender = sender_context(socket)

    case Communication.tell(sender, recipient, message) do
      {:ok, %{recipient_name: rname}} ->
        {:noreply,
         append_log(socket, %{
           kind: :private_tell_out,
           recipient: rname,
           text: message
         })}

      {:error, :empty} ->
        {:noreply, append_log(socket, %{kind: :system, text: "Tell #{recipient} what?"})}

      {:error, :too_long} ->
        {:noreply, append_log(socket, %{kind: :system, text: too_long_message()})}

      {:error, :not_found} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "There is no one named '#{recipient}' here or anywhere."
         })}

      {:error, :ambiguous} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "Multiple players match '#{recipient}'. Use the full unique name."
         })}

      {:error, :self_target} ->
        {:noreply, append_log(socket, %{kind: :system, text: "You can't tell yourself."})}

      {:error, :not_deliverable} ->
        {:noreply,
         append_log(socket, %{kind: :system, text: "Your message could not be delivered."})}
    end
  end

  def emote(socket, raw, said) do
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
    sender = sender_context(socket)

    case Communication.emote(sender, said) do
      :ok ->
        # No separate actor-side confirmation — the actor reads the
        # same broadcast every other room subscriber gets (FR-008).
        # The :emote_action log entry is appended in handle_info/2
        # just like for any witness.
        {:noreply, socket}

      {:error, :empty} ->
        {:noreply, append_log(socket, %{kind: :system, text: "Emote what?"})}

      {:error, :too_long} ->
        {:noreply, append_log(socket, %{kind: :system, text: too_long_message()})}
    end
  end

  @doc """
  NPC chat (feature 010). Routes to `NPCChat.send/3` which (a)
  validates input, (b) resolves the NPC token, (c) finds-or-starts
  the Conversation GenServer (cluster-aware via Horde.Registry),
  (d) returns the new-vs-continuing indicator synchronously. The
  reply itself arrives asynchronously as a `%ChatUtterance{}` on the
  player_topic.
  """
  def chat(socket, raw, npc_token, message) do
    socket = socket |> append_log(%{kind: :cmd, text: String.trim(raw)}) |> assign(:input, "")
    player_id = socket.assigns.current_player.id

    case AgenticRealms.World.NPCChat.send(player_id, npc_token, message) do
      {:ok, :new} ->
        # The :chat_new system message is broadcast by the
        # Conversation itself; we just leave the input cleared and
        # wait for it on player_topic. The reply will follow when
        # the LLM call lands.
        {:noreply, socket}

      {:ok, :continuing} ->
        {:noreply, socket}

      {:error, :empty_message} ->
        {:noreply, append_log(socket, %{kind: :system, text: "Chat about what?"})}

      {:error, :too_long} ->
        {:noreply, append_log(socket, %{kind: :system, text: too_long_message()})}

      {:error, :no_current_room} ->
        {:noreply, append_log(socket, %{kind: :system, text: "You are nowhere."})}

      {:error, {:no_such_npc, token}} ->
        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "You don't see #{token} here."
         })}

      {:error, {:ambiguous_npc, candidates}} ->
        names = Enum.join(candidates, ", ")

        {:noreply,
         append_log(socket, %{
           kind: :system,
           text: "There are several here. Which one — #{names}?"
         })}

      {:error, :still_thinking} ->
        # Defensive — the Conversation should broadcast its own
        # :chat_in_flight_rejection message; this is a fallback in
        # case the GenServer call path produced the error directly.
        {:noreply, socket}
    end
  end

  defp sender_context(socket) do
    %{
      id: socket.assigns.current_player.id,
      name: socket.assigns.stats.name,
      session_id: socket.assigns.session_id,
      room_id: socket.assigns.current_room_id
    }
  end

  defp too_long_message, do: "Your message is too long (max 500 characters)."
end
