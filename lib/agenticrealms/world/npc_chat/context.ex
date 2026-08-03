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

  alias AgenticRealms.Repo
  alias AgenticRealms.World.NPCChat.{SystemPrompt, Tools}
  alias AgenticRealms.World.PlayerNames
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Quests
  alias AgenticRealms.World.Schemas.{Blueprint, QuestInstance}

  import Ecto.Query, only: [from: 2]

  @max_tokens 256
  @object_short_desc_limit 200

  @type quest_context :: %{
          offerable_quests: [
            %{
              slug: String.t(),
              title: String.t(),
              narrative: String.t(),
              criteria_summary: String.t()
            }
          ],
          active_instances: [
            %{
              quest_id: String.t(),
              slug: String.t(),
              title: String.t(),
              progress: [Quests.criterion_progress()]
            }
          ],
          completed_slugs: [String.t()]
        }

  @type snapshot :: %{
          npc_name: String.t(),
          lore: String.t(),
          room_name: String.t(),
          room_description: String.t(),
          other_players: [String.t()],
          objects: [%{name: String.t(), short_description: String.t()}],
          player_name: String.t(),
          quest_context: quest_context()
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
      {:ok,
       %{
         npc_name: npc_clone.name,
         lore: npc_clone.lore || "",
         room_name: room_view.name,
         room_description: room_view.description,
         other_players: Enum.map(room_view.other_players, &display_name/1),
         objects: Enum.map(room_view.objects, &object_entry/1),
         player_name: PlayerNames.get(player_id),
         quest_context: quest_context(player_id, npc_clone.blueprint_id)
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Compute per-(viewer, NPC) quest context (feature 013).

  Returns a map with three lists:
    * `offerable_quests` — entries from the NPC's catalog that this
      player has neither completed nor currently has active with this
      NPC. These are the quests the LLM may choose to mention in prose.
    * `active_instances` — open quest instances this player has with
      this NPC, each with current per-criterion progress. The LLM uses
      the `quest_id` here when calling `check_progress` / `finalize_quest`.
    * `completed_slugs` — bare list of slugs this player has finished
      with this NPC. The LLM is told to react in-character to repeat
      requests without re-offering.
  """
  @spec quest_context(integer(), String.t() | nil) :: quest_context()
  def quest_context(_player_id, nil),
    do: %{offerable_quests: [], active_instances: [], completed_slugs: []}

  def quest_context(player_id, npc_blueprint_id)
      when is_integer(player_id) and is_binary(npc_blueprint_id) do
    blueprint = Repo.get(Blueprint, npc_blueprint_id)
    catalog = (blueprint && blueprint.quests) || []

    completed_slugs =
      from(q in QuestInstance,
        where:
          q.player_id == ^player_id and
            q.npc_blueprint_id == ^npc_blueprint_id and
            q.state == "completed",
        select: q.slug
      )
      |> Repo.all()

    active_rows =
      from(q in QuestInstance,
        where:
          q.player_id == ^player_id and
            q.npc_blueprint_id == ^npc_blueprint_id and
            q.state == "active",
        order_by: q.accepted_at
      )
      |> Repo.all()

    active_instances =
      Enum.map(active_rows, fn inst ->
        %{
          quest_id: inst.id,
          slug: inst.slug,
          title: inst.definition_snapshot["title"],
          progress: Quests.progress_for(inst)
        }
      end)

    active_slugs = MapSet.new(active_rows, & &1.slug)
    completed_set = MapSet.new(completed_slugs)

    offerable_quests =
      catalog
      |> Enum.reject(fn q ->
        slug = q["slug"]
        MapSet.member?(completed_set, slug) or MapSet.member?(active_slugs, slug)
      end)
      |> Enum.map(fn q ->
        %{
          slug: q["slug"],
          title: q["title"],
          narrative: q["narrative"],
          criteria_summary: criteria_summary(q["criteria"])
        }
      end)

    %{
      offerable_quests: offerable_quests,
      active_instances: active_instances,
      completed_slugs: completed_slugs
    }
  end

  defp criteria_summary(nil), do: ""

  defp criteria_summary(criteria) when is_list(criteria) do
    criteria
    |> Enum.map(fn c ->
      "Bring #{c["target_count"]} #{c["name"]}"
    end)
    |> Enum.join("; ")
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

  defp display_name(%{name: n}), do: n
  defp display_name(n) when is_binary(n), do: n

  defp object_entry(%{name: n, short_description: s}) do
    %{name: n, short_description: truncate(s, @object_short_desc_limit)}
  end

  defp truncate(nil, _), do: ""
  defp truncate(s, limit) when is_binary(s) and byte_size(s) <= limit, do: s
  defp truncate(s, limit) when is_binary(s), do: String.slice(s, 0, limit)
end
