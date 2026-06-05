defmodule AgenticRealms.World.Projections.QuestProjector do
  @moduledoc """
  Projector for the four finalize-side quest events (feature 013).

  Handler clauses:
    * `QuestItemsConsumed`     → delete consumed objects from `world_objects`
    * `QuestRewardMinted`      → insert the reward object into the player's
                                 inventory; back-reference on the quest row
    * `QuestCompleted`         → flip `quest_instances.state` to `"completed"`
    * `QuestItemsCleanedUp`    → delete any remaining quest-scoped objects
                                 belonging to that quest instance

  Each handler is idempotent under replay: `delete_all` over a closed
  id-set is a no-op the second time, `update_all` to a final value is
  idempotent, `insert(on_conflict: :nothing)` is idempotent.

  See `specs/013-quest-system/contracts/projector-quest.md`.
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :eventual

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.ContainerRef
  alias AgenticRealms.World.Commands.{CloneEntity, MoveEntity}
  alias AgenticRealms.World.Schemas.{Object, QuestInstance}

  alias AgenticRealms.World.Events.{
    QuestItemsConsumed,
    QuestRewardMinted,
    QuestCompleted,
    QuestItemsCleanedUp
  }

  def handle(%QuestItemsConsumed{consumed_object_ids: ids}, _meta) when is_list(ids) do
    if ids != [] do
      from(o in Object, where: o.id in ^ids)
      |> Repo.delete_all()
    end

    :ok
  end

  def handle(
        %QuestRewardMinted{
          quest_id: qid,
          player_id: pid,
          reward_object_id: oid,
          reward_name: name,
          reward_description: description
        },
        _meta
      ) do
    # Feature 016 — the reward is cloned into existence then moved into the
    # player's inventory, so it is a real entity they can drop. Deterministic
    # id (the reward_object_id) keeps this replay-safe.
    WorldApp.dispatch(%CloneEntity{
      entity_id: oid,
      kind: :object,
      fields: %{
        name: name,
        short_description: description,
        long_description: description,
        fixed: false,
        behaviors: [],
        quest_player_id: nil,
        quest_instance_id: nil
      }
    })

    WorldApp.dispatch(%MoveEntity{
      entity_id: oid,
      expected_from: ContainerRef.void(),
      to: ContainerRef.player(pid),
      cause: :spawned
    })

    # Back-reference the reward on the quest instance row so future
    # detail-rendering code (US3 Completed view) can show it without
    # parsing the snapshot.
    from(q in QuestInstance, where: q.id == ^qid)
    |> Repo.update_all(set: [reward_object_id: oid])

    :ok
  end

  def handle(
        %QuestCompleted{quest_id: qid, completed_at: at},
        _meta
      ) do
    completed_at = ensure_datetime(at)

    from(q in QuestInstance, where: q.id == ^qid)
    |> Repo.update_all(set: [state: "completed", completed_at: completed_at])

    :ok
  end

  def handle(%QuestItemsCleanedUp{remaining_quest_object_ids: ids}, _meta) when is_list(ids) do
    if ids != [] do
      from(o in Object, where: o.id in ^ids)
      |> Repo.delete_all()
    end

    :ok
  end

  defp ensure_datetime(%DateTime{} = dt), do: dt

  defp ensure_datetime(s) when is_binary(s) do
    {:ok, dt, _offset} = DateTime.from_iso8601(s)
    DateTime.truncate(dt, :second)
  end
end
