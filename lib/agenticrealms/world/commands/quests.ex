defmodule AgenticRealms.World.Commands.Quests do
  @moduledoc """
  Write-side facade for quests: accepting one from an NPC's
  catalog, checking progress, and finalizing.

  Split out of `AgenticRealms.World.Commands`, which had grown to cover every
  bounded concern in the world behind one module. `Commands` still delegates
  here, so callers are unchanged.
  """

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.Commands.{AcceptQuest, FinalizeQuest}
  alias AgenticRealms.World.Quests
  alias AgenticRealms.World.Schemas.{Blueprint, Object, QuestInstance}

  @doc """
  Accept the FetchQuest with slug `slug` from `npc_blueprint_id` on behalf
  of `player_id`. Pre-dispatch validation enforces FR-009:

    * `:unknown_npc` — blueprint doesn't exist
    * `:unknown_slug` — slug is not in the NPC's catalog
    * `:already_completed` — this player has already finished this quest
      with this NPC (sticky completion)
    * `{:already_active, existing_quest_id}` — this player already has
      this quest in flight with this NPC

  On success, generates a fresh `quest_id`, snapshots the catalog entry
  with instance-scoped quest tags, dispatches `AcceptQuest` to the Quest
  aggregate, and returns `{:ok, quest_id}`. The projector handler for
  `QuestAccepted` then inserts the `quest_instances` row and clones a
  quest-scoped item into each criterion's spawn rooms via the entity
  lifecycle.
  """
  @spec accept_quest(integer(), String.t(), String.t()) ::
          {:ok, String.t()}
          | {:error, :unknown_npc | :unknown_slug | :already_completed | term()}
          | {:error, :already_active, String.t()}
  def accept_quest(player_id, npc_blueprint_id, slug)
      when is_integer(player_id) and is_binary(npc_blueprint_id) and is_binary(slug) do
    with {:ok, catalog_entry} <- find_catalog_entry(npc_blueprint_id, slug),
         :ok <- check_no_existing_instance(player_id, npc_blueprint_id, slug) do
      quest_id = Ecto.UUID.generate()
      snapshot = build_definition_snapshot(catalog_entry, quest_id)
      accepted_at = DateTime.utc_now() |> DateTime.truncate(:second)

      case WorldApp.dispatch(
             %AcceptQuest{
               quest_id: quest_id,
               player_id: player_id,
               npc_blueprint_id: npc_blueprint_id,
               slug: slug,
               definition_snapshot: snapshot,
               accepted_at: accepted_at
             },
             consistency: :strong
           ) do
        :ok -> {:ok, quest_id}
        {:error, _} = err -> err
      end
    end
  end

  defp find_catalog_entry(npc_blueprint_id, slug) do
    case Repo.get(Blueprint, npc_blueprint_id) do
      nil ->
        {:error, :unknown_npc}

      %Blueprint{quests: catalog} ->
        case Enum.find(catalog || [], fn q -> q["slug"] == slug end) do
          nil -> {:error, :unknown_slug}
          entry -> {:ok, entry}
        end
    end
  end

  defp check_no_existing_instance(player_id, npc_blueprint_id, slug) do
    rows =
      from(q in QuestInstance,
        where:
          q.player_id == ^player_id and
            q.npc_blueprint_id == ^npc_blueprint_id and
            q.slug == ^slug
      )
      |> Repo.all()

    cond do
      Enum.any?(rows, &(&1.state == "completed")) ->
        {:error, :already_completed}

      active = Enum.find(rows, &(&1.state == "active")) ->
        {:error, :already_active, active.id}

      true ->
        :ok
    end
  end

  defp build_definition_snapshot(catalog_entry, quest_id) do
    short = String.slice(quest_id, 0, 8)

    rewritten_criteria =
      (catalog_entry["criteria"] || [])
      |> Enum.map(fn c ->
        instance_tag = "#{c["quest_tag"]}.#{short}"
        Map.put(c, "quest_tag", instance_tag)
      end)

    Map.put(catalog_entry, "criteria", rewritten_criteria)
  end

  @doc """
  Read-only progress check for an active quest. Returns the per-criterion
  count + target list, computed from current inventory. Refuses
  (`:unknown_instance`) if the quest doesn't exist, isn't active, or
  doesn't belong to this player.
  """
  @spec check_progress(integer(), String.t()) ::
          {:ok, [Quests.criterion_progress()]} | {:error, :unknown_instance}
  def check_progress(player_id, quest_id)
      when is_integer(player_id) and is_binary(quest_id) do
    case Quests.quest_instance(quest_id) do
      %QuestInstance{state: "active", player_id: ^player_id} = inst ->
        {:ok, Quests.progress_for(inst)}

      _ ->
        {:error, :unknown_instance}
    end
  end

  @doc """
  Finalize an active quest. Pre-dispatch validation reads the player's
  inventory (restricted to objects scoped to this quest instance) and
  matches against the snapshot criteria. On a fully satisfied quest,
  captures the exact object ids to consume + a pre-generated reward
  object id and dispatches `FinalizeQuest`. The aggregate then emits
  the four-event finalize bundle.

  Returns:
    * `{:ok, %{quest_id, reward_name, reward_description}}` on success
    * `{:error, :unknown_instance}` for nonexistent / wrong-player /
      already-completed instances
    * `{:error, :criteria_unmet, missing}` where `missing` is a
      `[%{name, count, target}]` list of criteria still short
  """
  @spec finalize_quest(integer(), String.t()) ::
          {:ok, %{quest_id: String.t(), reward_name: String.t(), reward_description: String.t()}}
          | {:error, :unknown_instance}
          | {:error, :criteria_unmet, [Quests.criterion_progress()]}
  def finalize_quest(player_id, quest_id)
      when is_integer(player_id) and is_binary(quest_id) do
    with %QuestInstance{state: "active", player_id: ^player_id} = inst <-
           Quests.quest_instance(quest_id) || :missing,
         {:ok, plan} <- build_finalize_plan(inst) do
      reward_object_id = Ecto.UUID.generate()
      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      reward = inst.definition_snapshot["reward"] || %{}
      reward_name = reward["name"] || "reward"
      reward_description = reward["description"] || ""
      reward_xp = normalize_xp(reward["xp"])

      case WorldApp.dispatch(
             %FinalizeQuest{
               quest_id: quest_id,
               consumed_object_ids: plan.consumed_object_ids,
               reward_object_id: reward_object_id,
               reward_name: reward_name,
               reward_description: reward_description,
               remaining_quest_object_ids: plan.remaining_quest_object_ids,
               completed_at: completed_at,
               reward_xp: reward_xp
             },
             consistency: :strong
           ) do
        :ok ->
          {:ok,
           %{
             quest_id: quest_id,
             reward_name: reward_name,
             reward_description: reward_description
           }}

        {:error, _} = err ->
          err
      end
    else
      :missing -> {:error, :unknown_instance}
      %QuestInstance{} -> {:error, :unknown_instance}
      {:error, :criteria_unmet, missing} -> {:error, :criteria_unmet, missing}
    end
  end

  defp normalize_xp(xp) when is_integer(xp) and xp > 0, do: xp
  defp normalize_xp(_), do: 0

  defp build_finalize_plan(%QuestInstance{
         id: qid,
         player_id: pid,
         definition_snapshot: snapshot
       }) do
    all_objects =
      from(o in Object, where: o.quest_instance_id == ^qid)
      |> Repo.all()

    {in_inventory, elsewhere} =
      Enum.split_with(all_objects, fn o ->
        o.container_type == "player" and o.container_id == Integer.to_string(pid)
      end)

    criteria = snapshot["criteria"] || []

    {consumed, missing} = match_criteria(criteria, in_inventory)

    if missing != [] do
      {:error, :criteria_unmet, missing}
    else
      consumed_ids = Enum.map(consumed, & &1.id)
      uncollected_ids = Enum.map(elsewhere, & &1.id)
      extra_in_inventory_ids = Enum.map(in_inventory -- consumed, & &1.id)

      {:ok,
       %{
         consumed_object_ids: consumed_ids,
         remaining_quest_object_ids: uncollected_ids ++ extra_in_inventory_ids
       }}
    end
  end

  defp match_criteria(criteria, in_inventory) do
    Enum.reduce(criteria, {[], []}, fn criterion, {consumed_acc, missing_acc} ->
      tag = criterion["quest_tag"]
      target = criterion["target_count"] || 0
      name = criterion["name"] || ""

      matches =
        Enum.filter(in_inventory, fn o ->
          Enum.any?(o.behaviors || [], fn b ->
            (b["type"] || Map.get(b, :type)) == "quest_tag" and
              (b["tag"] || Map.get(b, :tag)) == tag
          end)
        end)

      cond do
        length(matches) < target ->
          {consumed_acc, missing_acc ++ [%{name: name, count: length(matches), target: target}]}

        true ->
          taken = Enum.take(matches, target)
          {consumed_acc ++ taken, missing_acc}
      end
    end)
  end
end
