defmodule AgenticRealms.World.NPCChat.Conversation do
  @moduledoc """
  Per-(player, NPC clone) chat process (feature 010).

  Holds the rolling conversation history, fronts the Anthropic call via
  an async Task, enforces the FR-020 in-flight lockout, and self-
  terminates after 60s of inactivity via the GenServer built-in idle
  `:timeout` mechanism. State is volatile — nothing is persisted.

  Registered cluster-wide via `Horde.Registry` under
  `{NPCChat.Registry, {player_id, npc_clone_id}}`. Started under
  `NPCChat.Supervisor` (a `Horde.DynamicSupervisor`).

  See `specs/010-npc-conversations/contracts/conversation.md`.
  """

  use GenServer

  require Logger

  alias AgenticRealms.Anthropic
  alias AgenticRealms.World.NPCChat.{Context, Registry, Reply}
  alias AgenticRealms.World.UIEvents.{ChatSystemMessage, ChatUtterance}
  alias AgenticRealmsWeb.Topics

  @pubsub AgenticRealms.PubSub
  @history_cap_pairs 20
  @new_window_ms 60_000

  defstruct [
    :player_id,
    :npc_clone_id,
    :npc_name,
    :lore,
    :npc_clone,
    :task_ref,
    :pending_player_message,
    turns: [],
    pending?: false,
    last_activity_at: nil
  ]

  @type t :: %__MODULE__{
          player_id: integer(),
          npc_clone_id: String.t(),
          npc_name: String.t(),
          lore: String.t(),
          npc_clone: term(),
          task_ref: reference() | nil,
          pending_player_message: String.t() | nil,
          turns: list(),
          pending?: boolean(),
          last_activity_at: integer() | nil
        }

  # --- Client -----------------------------------------------------------

  @doc """
  Start a Conversation registered under `{player_id, npc_clone_id}` via
  `Horde.Registry`. Init args: `{player_id, npc_clone_struct}`.
  """
  def start_link({player_id, %{id: clone_id} = clone}) do
    GenServer.start_link(__MODULE__, {player_id, clone},
      name: Registry.via_tuple({player_id, clone_id})
    )
  end

  # --- Server -----------------------------------------------------------

  @impl true
  def init({player_id, clone}) do
    state = %__MODULE__{
      player_id: player_id,
      npc_clone_id: clone.id,
      npc_name: clone.name,
      lore: clone.lore || "",
      npc_clone: clone
    }

    {:ok, state, idle_timeout()}
  end

  @impl true
  def handle_call({:send, player_id, message}, _from, %__MODULE__{} = state)
      when state.player_id == player_id do
    cond do
      state.pending? ->
        {:reply, {:error, :still_thinking}, state, idle_timeout()}

      true ->
        now = System.monotonic_time(:millisecond)
        new_or_continuing = classify(state.last_activity_at, now)

        # On :new, drop any stale history from a prior conversation
        # that somehow survived idle reap (defensive; should not happen).
        turns_after_classify =
          case new_or_continuing do
            :new -> []
            :continuing -> state.turns
          end

        broadcast_system_message(state, new_or_continuing)

        pid = state.player_id
        clone = state.npc_clone
        history_for_call = turns_after_classify

        task =
          Task.Supervisor.async_nolink(
            AgenticRealms.World.NPCChat.TaskSupervisor,
            fn -> dispatch_llm(pid, clone, history_for_call, message) end
          )

        new_state = %__MODULE__{
          state
          | turns: turns_after_classify,
            pending?: true,
            pending_player_message: message,
            last_activity_at: now,
            task_ref: task.ref
        }

        {:reply, {:ok, new_or_continuing}, new_state, idle_timeout()}
    end
  end

  # Test-only inspection.
  def handle_call(:get_state, _from, state) do
    {:reply, state, state, idle_timeout()}
  end

  @impl true
  def handle_info({ref, result}, %__MODULE__{task_ref: ref} = state) when is_reference(ref) do
    # Task completed normally — demonitor and discard the upcoming :DOWN.
    Process.demonitor(ref, [:flush])
    handle_llm_result(result, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{task_ref: ref} = state) do
    # Task died with a non-normal exit — treat as failure.
    Logger.warning("NPCChat Task crashed: #{inspect(reason)}")
    handle_llm_result({:error, {:task_crash, reason}}, state)
  end

  def handle_info(:timeout, %__MODULE__{} = state) do
    Logger.debug(
      "NPCChat Conversation idle-reaped: player=#{state.player_id} clone=#{state.npc_clone_id}"
    )

    {:stop, :normal, state}
  end

  def handle_info(_other, state) do
    {:noreply, state, idle_timeout()}
  end

  # --- Result handling --------------------------------------------------

  defp handle_llm_result({:ok, response_body}, state) do
    case Reply.parse(response_body) do
      {:speech, text} -> handle_success(:chat_speech, :speech, text, state)
      {:emote, text} -> handle_success(:chat_emote, :emote, text, state)
      {:error, :malformed} -> handle_failure(state, :malformed_output)
    end
  end

  defp handle_llm_result({:error, reason}, state) do
    handle_failure(state, reason)
  end

  defp handle_success(utterance_kind, mode, text, %__MODULE__{} = state) do
    new_turns =
      (state.turns ++
         [
           %{role: :player, text: state.pending_player_message},
           %{role: :npc, text: text, mode: mode}
         ])
      |> trim_history()

    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.player_topic(state.player_id),
      %ChatUtterance{
        kind: utterance_kind,
        npc_clone_id: state.npc_clone_id,
        npc_name: state.npc_name,
        text: text,
        triggering_player_id: state.player_id
      }
    )

    new_state = %__MODULE__{
      state
      | turns: new_turns,
        pending?: false,
        pending_player_message: nil,
        task_ref: nil
    }

    {:noreply, new_state, idle_timeout()}
  end

  defp handle_failure(%__MODULE__{} = state, _reason) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.player_topic(state.player_id),
      %ChatSystemMessage{
        kind: :chat_fallback,
        npc_name: state.npc_name,
        text: "#{state.npc_name} seems lost in thought.",
        player_id: state.player_id
      }
    )

    new_state = %__MODULE__{
      state
      | pending?: false,
        pending_player_message: nil,
        task_ref: nil
    }

    {:noreply, new_state, idle_timeout()}
  end

  # --- Helpers ----------------------------------------------------------

  defp broadcast_system_message(state, :new) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.player_topic(state.player_id),
      %ChatSystemMessage{
        kind: :chat_new,
        npc_name: state.npc_name,
        text: "You begin a conversation with #{state.npc_name}.",
        player_id: state.player_id
      }
    )
  end

  defp broadcast_system_message(state, :continuing) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      Topics.player_topic(state.player_id),
      %ChatSystemMessage{
        kind: :chat_continuing,
        npc_name: state.npc_name,
        text: "You continue your conversation with #{state.npc_name}.",
        player_id: state.player_id
      }
    )
  end

  defp classify(nil, _now), do: :new

  defp classify(last_activity_at, now)
       when is_integer(last_activity_at) and is_integer(now) do
    if now - last_activity_at > @new_window_ms, do: :new, else: :continuing
  end

  defp trim_history(turns) do
    pair_count = div(length(turns), 2)

    if pair_count > @history_cap_pairs do
      drop = (pair_count - @history_cap_pairs) * 2
      Enum.drop(turns, drop)
    else
      turns
    end
  end

  defp dispatch_llm(player_id, clone, turns, message) do
    case Context.snapshot(player_id, clone) do
      {:ok, snapshot} ->
        request = Context.build_request(snapshot, turns, message)
        Anthropic.create_message(request)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp idle_timeout do
    Application.get_env(:agenticrealms, AgenticRealms.World.NPCChat, [])
    |> Keyword.get(:idle_timeout_ms, 60_000)
  end
end
