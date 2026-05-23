defmodule AgenticRealms.World.Projections.WorldProjector do
  @moduledoc """
  Projects every room / exit / object domain event into the `world_rooms`,
  `world_exits`, and `world_objects` Ecto-backed read models.

  Event handler clauses added so far:
    * Phase 3 (US5): RoomCreated, ExitAdded, ObjectPlacedInRoom
    * Phase 6 (US3): ObjectTakenFromRoom, ObjectDroppedInRoom
    * Feature 007: NPCSpawnedInRoom

  Every insert uses `on_conflict: :nothing` so the projector is safe to
  replay against a partially-populated read model (which happens on a fresh
  subscription after an `event_store.reset`).
  """

  # `:strong` so callers (Commands.take, Commands.drop) can dispatch with
  # `consistency: :strong` and be guaranteed the read model reflects the
  # event by the time the dispatch returns. Without this, `list_inventory`
  # called immediately after `take/2` would see stale state.
  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :strong

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Direction

  alias AgenticRealms.World.Events.{
    RoomCreated,
    ExitAdded,
    ObjectPlacedInRoom,
    ObjectTakenFromRoom,
    ObjectDroppedInRoom,
    NPCSpawnedInRoom
  }

  alias AgenticRealms.World.Schemas.{Room, Exit, Object, NPC}

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

  def handle(
        %NPCSpawnedInRoom{
          room_id: room_id,
          npc_id: nid,
          name: name,
          short_description: short,
          long_description: long
        },
        _meta
      ) do
    Repo.insert!(
      %NPC{
        id: nid,
        name: name,
        short_description: short,
        long_description: long,
        room_id: room_id
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
