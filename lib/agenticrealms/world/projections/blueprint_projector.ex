defmodule AgenticRealms.World.Projections.BlueprintProjector do
  @moduledoc """
  Feature 015 — projects unified Blueprint events into the `blueprints`
  read-model table. Replaces `ObjectBlueprintProjector` and the
  `NPCBlueprintCreated` handler that lived in `WorldProjector`.

    * `BlueprintCreated` → row insert (`on_conflict: :nothing`, replay-safe).
    * `BlueprintEdited` → sparse update guarded by `revision < new_revision`
      so an already-applied edit is a no-op under replay.
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :strong

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Events.{BlueprintCreated, BlueprintEdited}
  alias AgenticRealms.World.Schemas.Blueprint

  def handle(%BlueprintCreated{} = e, _meta) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    row = %Blueprint{
      id: e.blueprint_id,
      kind: Map.get(e, :kind) || "npc",
      name: e.name,
      short_description: e.short_description,
      long_description: e.long_description,
      fixed: Map.get(e, :fixed, false),
      revision: Map.get(e, :revision, 1),
      behaviors: Map.get(e, :behaviors, []) || [],
      lore: Map.get(e, :lore, "") || "",
      toolsets: Map.get(e, :toolsets, []) || [],
      quests: Map.get(e, :quests, []) || [],
      inserted_at: now,
      updated_at: now
    }

    Repo.insert!(row, on_conflict: :nothing, conflict_target: :id)
    :ok
  end

  def handle(%BlueprintEdited{} = e, _meta) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    updates =
      e.fields_changed
      |> Map.put(:revision, e.revision)
      |> Map.put(:updated_at, now)
      |> Map.to_list()

    from(b in Blueprint, where: b.id == ^e.blueprint_id and b.revision < ^e.revision)
    |> Repo.update_all(set: updates)

    :ok
  end
end
