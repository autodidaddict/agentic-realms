defmodule AgenticRealms.World.Quests do
  @moduledoc """
  Read-side API for the quest system (feature 013). Pure Ecto reads
  against `quest_instances` and `world_objects` — no Commanded dispatch.

  Quest progress is a pure function of the player's current inventory
  (FR-019). This module is the canonical place to compute it.

  See `specs/013-quest-system/data-model.md` § 11 for the API shapes.
  """

  import Ecto.Query

  alias AgenticRealms.World.EventData
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Schemas.{Object, QuestInstance}

  @type criterion_progress :: %{name: String.t(), count: non_neg_integer(), target: pos_integer()}

  @type active_quest_summary :: %{
          quest_id: String.t(),
          title: String.t(),
          narrative: String.t(),
          criteria: [criterion_progress()]
        }

  @type completed_quest_summary :: %{
          quest_id: String.t(),
          title: String.t(),
          completed_at: DateTime.t(),
          reward_name: String.t() | nil
        }

  @doc """
  Active quest instances for a player, ordered by accept time.
  Each entry includes the title, narrative, and per-criterion progress
  computed from current inventory.
  """
  @spec active_for(integer()) :: [active_quest_summary()]
  def active_for(player_id) when is_integer(player_id) do
    from(q in QuestInstance,
      where: q.player_id == ^player_id and q.state == "active",
      order_by: q.accepted_at
    )
    |> Repo.all()
    |> Enum.map(fn inst ->
      %{
        quest_id: inst.id,
        title: EventData.get(inst.definition_snapshot, "title"),
        narrative: EventData.get(inst.definition_snapshot, "narrative"),
        criteria: progress_for(inst)
      }
    end)
  end

  @doc """
  Completed quest instances for a player, ordered by completion time
  (most recent first). Lifetime-retained per FR-025.
  """
  @spec history_for(integer()) :: [completed_quest_summary()]
  def history_for(player_id) when is_integer(player_id) do
    from(q in QuestInstance,
      where: q.player_id == ^player_id and q.state == "completed",
      order_by: [desc: q.completed_at]
    )
    |> Repo.all()
    |> Enum.map(fn inst ->
      %{
        quest_id: inst.id,
        title: EventData.get(inst.definition_snapshot, "title"),
        completed_at: inst.completed_at,
        reward_name: EventData.get(inst.definition_snapshot, ["reward", "name"])
      }
    end)
  end

  @doc """
  Fetch a single quest instance by id. Returns nil if not found.
  """
  @spec quest_instance(String.t()) :: QuestInstance.t() | nil
  def quest_instance(quest_id) when is_binary(quest_id) do
    Repo.get(QuestInstance, quest_id)
  end

  @doc """
  Per-criterion progress for an active quest. Reads the player's quest-
  scoped inventory and matches behaviors-encoded `quest_tag` entries
  against each criterion in the snapshot.

  Returns `[%{name, count, target}, ...]` in the same order the criteria
  appear in the snapshot.
  """
  @spec progress_for(QuestInstance.t()) :: [criterion_progress()]
  def progress_for(%QuestInstance{id: qid, player_id: pid, definition_snapshot: snapshot}) do
    inventory_items =
      from(o in Object,
        where:
          o.quest_instance_id == ^qid and
            o.container_type == "player" and o.container_id == ^Integer.to_string(pid)
      )
      |> Repo.all()

    snapshot
    |> EventData.get("criteria")
    |> List.wrap()
    |> Enum.map(fn criterion ->
      tag = EventData.get(criterion, "quest_tag")
      target = EventData.get(criterion, "target_count") || 0
      name = EventData.get(criterion, "name") || ""
      count = Enum.count(inventory_items, fn obj -> has_quest_tag?(obj, tag) end)
      %{name: name, count: count, target: target}
    end)
  end

  @doc """
  Active quests for `player_id` whose criteria reference any quest_tag
  carried by the given object. Used by the broadcaster to decide which
  PlayerQuestProgress events to emit on pickup/drop.

  Returns the full QuestInstance structs so the caller can compute
  progress directly.
  """
  @spec active_quests_referencing_object(integer(), String.t()) :: [QuestInstance.t()]
  def active_quests_referencing_object(player_id, object_id)
      when is_integer(player_id) and is_binary(object_id) do
    case Repo.get(Object, object_id) do
      nil ->
        []

      %Object{behaviors: behaviors} ->
        tags = quest_tags_from_behaviors(behaviors || [])

        if tags == [] do
          []
        else
          from(q in QuestInstance,
            where: q.player_id == ^player_id and q.state == "active"
          )
          |> Repo.all()
          |> Enum.filter(fn inst ->
            inst.definition_snapshot
            |> EventData.get("criteria")
            |> List.wrap()
            |> Enum.any?(fn c -> EventData.get(c, "quest_tag") in tags end)
          end)
        end
    end
  end

  # ----- private helpers ---------------------------------------------------

  # The `definition_snapshot` jsonb column comes back from Ecto with string
  # keys regardless of how it was written (Postgres jsonb -> Elixir map).
  # We support atom-keyed lookups too for defensive parity in case the
  # value ever arrives via the eventstore atom-keying path.

  defp has_quest_tag?(_, nil), do: false

  defp has_quest_tag?(%Object{behaviors: behaviors}, tag) do
    Enum.any?(behaviors || [], fn b ->
      type = b["type"] || Map.get(b, :type)
      btag = b["tag"] || Map.get(b, :tag)
      type == "quest_tag" and btag == tag
    end)
  end

  defp quest_tags_from_behaviors(behaviors) do
    behaviors
    |> Enum.filter(fn b ->
      type = b["type"] || Map.get(b, :type)
      type == "quest_tag"
    end)
    |> Enum.map(fn b -> b["tag"] || Map.get(b, :tag) end)
    |> Enum.reject(&is_nil/1)
  end
end
