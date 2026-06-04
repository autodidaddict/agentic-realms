defmodule AgenticRealms.World.Projections.ObjectBlueprintProjector do
  @moduledoc """
  Feature 014 — projects Object Blueprint domain events into the
  `object_blueprints` read-model table.

  Event handlers landed per user story:
    * US1: `ObjectBlueprintCreated` → row insert.
    * US5: `ObjectBlueprintEdited` → row update + revision bump.

  Insert uses `on_conflict: :nothing` so replay against a partially-
  populated read model is safe.

  See `specs/014-item-blueprints/contracts/events.md` for the projection
  contracts.
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :strong

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Events.{ObjectBlueprintCreated, ObjectBlueprintEdited}
  alias AgenticRealms.World.Schemas.ObjectBlueprint

  def handle(%ObjectBlueprintCreated{} = e, _meta) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    row = %ObjectBlueprint{
      id: e.blueprint_id,
      kind: e.kind,
      name: e.name,
      short_description: e.short_description,
      long_description: e.long_description,
      fixed: e.fixed,
      revision: e.revision,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert!(row, on_conflict: :nothing, conflict_target: :id)
    :ok
  end

  # Feature 014 US5 — edit projection. Replay-safe via the `revision <
  # new_revision` guard: an already-applied edit becomes a no-op.
  def handle(%ObjectBlueprintEdited{} = e, _meta) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    updates =
      e.fields_changed
      |> Map.put(:revision, e.revision)
      |> Map.put(:updated_at, now)
      |> Map.to_list()

    from(b in ObjectBlueprint,
      where: b.id == ^e.blueprint_id and b.revision < ^e.revision
    )
    |> Repo.update_all(set: updates)

    :ok
  end
end
