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
  alias AgenticRealms.World.Commands, as: WorldCommands
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

  @doc """
  Start a Conversation registered under `{player_id, npc_clone_id}` via
  `Horde.Registry`. Init args: `{player_id, npc_clone_struct}`.
  """
  @spec start_link({integer(), map()}) :: GenServer.on_start()
  def start_link({player_id, %{id: clone_id} = clone}) do
    GenServer.start_link(__MODULE__, {player_id, clone},
      name: Registry.via_tuple({player_id, clone_id})
    )
  end

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

  def handle_call(:get_state, _from, state) do
    {:reply, state, state, idle_timeout()}
  end

  @impl true
  def handle_info({ref, result}, %__MODULE__{task_ref: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    handle_llm_result(result, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{task_ref: ref} = state) do
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

  defp handle_llm_result({:ok, response_body}, state) do
    case Reply.parse(response_body) do
      {:speech, text} -> handle_success(:chat_speech, :speech, text, state)
      {:emote, text} -> handle_success(:chat_emote, :emote, text, state)
      {:tool_call, call} -> handle_tool_call(call, state)
      {:error, :malformed} -> handle_failure(state, :malformed_output)
    end
  end

  defp handle_llm_result({:error, reason}, state) do
    handle_failure(state, reason)
  end

  defp handle_tool_call(%{name: "accept_quest", input: %{"slug" => slug}}, state) do
    case WorldCommands.accept_quest(state.player_id, state.npc_clone.blueprint_id, slug) do
      {:ok, _quest_id} ->
        text = accept_quest_emote_text(state.npc_name, :ok)
        handle_success(:chat_emote, :emote, text, state)

      {:error, :already_active, _qid} ->
        text = accept_quest_emote_text(state.npc_name, {:error, :already_active})
        handle_success(:chat_emote, :emote, text, state)

      {:error, reason} ->
        text = accept_quest_emote_text(state.npc_name, {:error, reason})
        handle_success(:chat_emote, :emote, text, state)
    end
  end

  defp handle_tool_call(%{name: "check_progress", input: %{"quest_id" => qid}}, state) do
    case WorldCommands.check_progress(state.player_id, qid) do
      {:ok, criteria} ->
        text = check_progress_emote_text(criteria)
        handle_success(:chat_emote, :emote, text, state)

      {:error, _reason} ->
        handle_success(
          :chat_emote,
          :emote,
          "looks puzzled, as if they can't quite place which errand you mean.",
          state
        )
    end
  end

  defp handle_tool_call(%{name: "finalize_quest", input: %{"quest_id" => qid}}, state) do
    case WorldCommands.finalize_quest(state.player_id, qid) do
      {:ok, %{reward_name: reward}} ->
        handle_success(
          :chat_emote,
          :emote,
          "beams and presses a #{reward} into your hand. \"You have my thanks, truly.\"",
          state
        )

      {:error, :criteria_unmet, missing} ->
        text = criteria_unmet_emote_text(missing)
        handle_success(:chat_emote, :emote, text, state)

      {:error, _reason} ->
        handle_success(
          :chat_emote,
          :emote,
          "looks confused, as if they cannot quite remember promising you anything.",
          state
        )
    end
  end

  defp handle_tool_call(_unknown, state) do
    handle_failure(state, :unknown_tool_call)
  end

  defp check_progress_emote_text(criteria) do
    if Enum.all?(criteria, fn c -> c.count >= c.target end) do
      "looks at your hands and gives a small approving nod. \"That's all of them. Say the word and we're settled.\""
    else
      summary =
        criteria
        |> Enum.map(fn c -> "#{c.name} #{c.count}/#{c.target}" end)
        |> Enum.join(", ")

      "tilts her head, considering. \"Still on the way then — #{summary}.\""
    end
  end

  defp criteria_unmet_emote_text(missing) do
    summary =
      missing
      |> Enum.map(fn c -> "#{c.name} #{c.count}/#{c.target}" end)
      |> Enum.join(", ")

    "looks at your empty hands and gently shakes her head. \"Not quite yet — you're still short #{summary}.\""
  end

  defp accept_quest_emote_text(_npc_name, :ok),
    do: "nods solemnly. \"Good. You have my thanks already — bring them when you can.\""

  defp accept_quest_emote_text(_npc_name, {:error, :already_completed}),
    do: "smiles gently and waves a hand. \"You've already done me that favor, friend.\""

  defp accept_quest_emote_text(_npc_name, {:error, :already_active}),
    do: "raises a knowing eyebrow. \"You're already on that errand.\""

  defp accept_quest_emote_text(_npc_name, {:error, :unknown_slug}),
    do: "tilts their head, puzzled, as if they don't quite follow."

  defp accept_quest_emote_text(_npc_name, {:error, _other}),
    do: "frowns and shakes their head, troubled by something they can't quite name."

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
