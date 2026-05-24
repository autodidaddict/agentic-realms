defmodule AgenticRealms.World.Projections.WorldProjector do
  @moduledoc """
  Projects every room / exit / object / NPC domain event into the
  `world_rooms`, `world_exits`, `world_objects`, `npc_blueprints`, and
  `npc_clones` Ecto-backed read models.

  Event handler clauses added so far:
    * Phase 3 (US5): RoomCreated, ExitAdded, ObjectPlacedInRoom
    * Phase 6 (US3): ObjectTakenFromRoom, ObjectDroppedInRoom
    * Feature 007: NPCSpawnedInRoom (REWRITTEN in 008 — see below)
    * Feature 008: NPCBlueprintCreated, NPCClonedFromBlueprint

  Every insert uses `on_conflict: :nothing` so the projector is safe to
  replay against a partially-populated read model.

  **Feature 008 — legacy NPCSpawnedInRoom handling**: the feature 007 event
  type is preserved in the event store; this projector handles it by
  deriving a deterministic synthetic blueprint id, upserting a blueprint
  row with `is_synthetic: true`, then inserting the clone with a serial
  computed via a MAX query against the existing clones for that blueprint.
  See `specs/008-npc-blueprints/contracts/projector.md`.
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :strong

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Direction
  alias AgenticRealms.World.Projections.SyntheticBlueprintId

  alias AgenticRealms.World.Events.{
    RoomCreated,
    ExitAdded,
    ObjectPlacedInRoom,
    ObjectTakenFromRoom,
    ObjectDroppedInRoom,
    NPCSpawnedInRoom,
    NPCBlueprintCreated,
    NPCClonedFromBlueprint
  }

  alias AgenticRealms.World.Schemas.{Room, Exit, Object, NPCBlueprint, NPCClone}

  def handle(%RoomCreated{room_id: id, name: name, description: description}, _meta) do
    Repo.insert!(
      %Room{id: id, name: name, description: description},
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  def handle(
        %ExitAdded{room_id: source, direction: direction, target_room_id: target},
        _meta
      ) do
    Repo.insert!(
      %Exit{
        source_room_id: source,
        direction: Direction.to_string(direction),
        target_room_id: target
      },
      on_conflict: :nothing,
      conflict_target: [:source_room_id, :direction]
    )

    :ok
  end

  def handle(
        %ObjectPlacedInRoom{
          room_id: room_id,
          object_id: oid,
          name: name,
          short_description: short,
          long_description: long,
          fixed: fixed
        },
        _meta
      ) do
    Repo.insert!(
      %Object{
        id: oid,
        name: name,
        short_description: short,
        long_description: long,
        fixed: fixed,
        room_id: room_id,
        player_id: nil
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  def handle(%ObjectTakenFromRoom{player_id: pid, object_id: oid}, _meta) do
    {1, _} =
      Repo.update_all(
        from(o in Object, where: o.id == ^oid),
        set: [room_id: nil, player_id: pid, updated_at: utc_now()]
      )

    :ok
  end

  def handle(%ObjectDroppedInRoom{room_id: rid, object_id: oid}, _meta) do
    {1, _} =
      Repo.update_all(
        from(o in Object, where: o.id == ^oid),
        set: [room_id: rid, player_id: nil, updated_at: utc_now()]
      )

    :ok
  end

  # Feature 008: authored blueprints (from CreateNPCBlueprint command).
  def handle(
        %NPCBlueprintCreated{
          blueprint_id: bp_id,
          name: name,
          short_description: short,
          long_description: long
        },
        _meta
      ) do
    Repo.insert!(
      %NPCBlueprint{
        id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        is_synthetic: false
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  # Feature 008: clone insertion from the event's denormalized payload.
  # The blueprint table is NOT consulted here — the event already contains
  # the full-copy snapshot of the blueprint's data as of clone time.
  def handle(
        %NPCClonedFromBlueprint{
          blueprint_id: bp_id,
          clone_id: cid,
          room_id: rid,
          serial: serial,
          name: name,
          short_description: short,
          long_description: long
        },
        _meta
      ) do
    Repo.insert!(
      %NPCClone{
        id: cid,
        blueprint_id: bp_id,
        serial: serial,
        name: name,
        short_description: short,
        long_description: long,
        room_id: rid
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  # Feature 008 — legacy event from feature 007. Synthesizes a blueprint
  # id from the payload, upserts it, computes the next serial via MAX,
  # then inserts the clone. Deterministic + idempotent under replay.
  def handle(
        %NPCSpawnedInRoom{
          room_id: rid,
          npc_id: nid,
          name: name,
          short_description: short,
          long_description: long
        },
        _meta
      ) do
    bp_id = SyntheticBlueprintId.derive(name, short, long)

    Repo.insert!(
      %NPCBlueprint{
        id: bp_id,
        name: name,
        short_description: short,
        long_description: long,
        is_synthetic: true
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    serial = next_serial_for_blueprint(bp_id)

    Repo.insert!(
      %NPCClone{
        id: nid,
        blueprint_id: bp_id,
        serial: serial,
        name: name,
        short_description: short,
        long_description: long,
        room_id: rid
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  defp next_serial_for_blueprint(bp_id) do
    from(c in NPCClone, where: c.blueprint_id == ^bp_id, select: max(c.serial))
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
