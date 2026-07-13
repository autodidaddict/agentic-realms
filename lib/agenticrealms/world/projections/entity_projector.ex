defmodule AgenticRealms.World.Projections.EntityProjector do
  @moduledoc """
  Feature 016 — projects the unified entity lifecycle (`EntityCloned` /
  `EntityMoved` / `EntityEdited`) into the read models. Owns every
  `world_objects` (and, from Phase 4, `npc_clones`) row write.

  `EntityCloned` inserts the row in the void; `EntityMoved` updates the
  typed container; `EntityEdited` applies a sparse field diff. The event's
  `kind` routes to the right table. All handlers are replay-safe
  (`on_conflict: :nothing` on insert; absolute/sparse updates).
  """

  use Commanded.Event.Handler,
    application: AgenticRealms.World.Application,
    name: __MODULE__,
    consistency: :strong

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.ContainerRef
  alias AgenticRealms.World.Events.{EntityCloned, EntityMoved, EntityEdited, EntityRemoved}
  alias AgenticRealms.World.Schemas.{Object, NPCClone}

  @object_edit_fields ~w(name short_description long_description fixed behaviors)a
  # Feature 015 US7 — in-place NPC clone edit. The clone is freestanding, so
  # its behaviors are edited directly (the effective set).
  @npc_edit_fields ~w(name short_description long_description fixed lore behaviors behavior_groups direct_behaviors)a

  # --- EntityCloned: insert the read row in the void ----------------------

  def handle(%EntityCloned{kind: kind, entity_id: id, fields: fields}, _meta) do
    case norm_kind(kind) do
      :object -> insert_object(id, fields)
      :npc -> insert_npc(id, fields)
    end
  end

  # --- EntityMoved: absolute container assignment -------------------------

  def handle(%EntityMoved{kind: kind, entity_id: id, to: to}, _meta) do
    container = ContainerRef.from_map(to)

    case norm_kind(kind) do
      :object ->
        from(o in Object, where: o.id == ^id)
        |> Repo.update_all(
          set: [
            container_type: Atom.to_string(container.type),
            container_id: container_id_string(container),
            updated_at: utc_now()
          ]
        )

        :ok

      :npc ->
        # NPCs live only in rooms; the read row uses `room_id` (denormalized,
        # not a live FK). A move into a room sets it; a move into the void
        # clears it.
        room_id = if container.type == :room, do: container.id, else: nil

        from(c in NPCClone, where: c.id == ^id)
        |> Repo.update_all(set: [room_id: room_id, updated_at: utc_now()])

        :ok
    end
  end

  # --- EntityEdited: sparse in-place field diff ---------------------------

  def handle(%EntityEdited{kind: kind, entity_id: id, fields_changed: changed}, _meta) do
    case norm_kind(kind) do
      :object ->
        updates =
          changed
          |> atomize_fields(@object_edit_fields)
          |> Map.put(:updated_at, utc_now())
          |> Map.to_list()

        from(o in Object, where: o.id == ^id)
        |> Repo.update_all(set: updates)

        :ok

      :npc ->
        updates =
          changed
          |> atomize_fields(@npc_edit_fields)
          |> Map.put(:updated_at, utc_now())
          |> Map.to_list()

        from(c in NPCClone, where: c.id == ^id)
        |> Repo.update_all(set: updates)

        :ok
    end
  end

  # --- EntityRemoved: delete the read-model row ---------------------------

  # Feature 018 — removal deletes the denormalized row. Delete-by-pk is
  # idempotent/replay-safe (0 rows when already gone). Deleting the `npc_clones`
  # row is load-bearing: the NPC-mind reconciler treats the live rows as the set
  # of NPCs that should have a mind, so a stale row would resurrect a terminated
  # mind on the next sweep.
  def handle(%EntityRemoved{kind: kind, entity_id: id}, _meta) do
    case norm_kind(kind) do
      :object ->
        from(o in Object, where: o.id == ^id) |> Repo.delete_all()
        :ok

      :npc ->
        from(c in NPCClone, where: c.id == ^id) |> Repo.delete_all()
        :ok
    end
  end

  # --- helpers ------------------------------------------------------------

  defp insert_object(id, fields) do
    Repo.insert!(
      %Object{
        id: id,
        name: fval(fields, :name),
        short_description: fval(fields, :short_description),
        long_description: fval(fields, :long_description),
        fixed: fval(fields, :fixed) || false,
        behaviors: fval(fields, :behaviors) || [],
        quest_player_id: fval(fields, :quest_player_id),
        quest_instance_id: fval(fields, :quest_instance_id),
        container_type: "void",
        container_id: nil
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  defp insert_npc(id, fields) do
    Repo.insert!(
      %NPCClone{
        id: id,
        blueprint_id: fval(fields, :blueprint_id),
        name: fval(fields, :name),
        short_description: fval(fields, :short_description),
        long_description: fval(fields, :long_description),
        behaviors: fval(fields, :behaviors) || [],
        lore: fval(fields, :lore) || "",
        # Feature 015 — authoring/extract provenance (default for freeform NPCs).
        fixed: fval(fields, :fixed) || false,
        behavior_groups: fval(fields, :behavior_groups) || [],
        direct_behaviors: fval(fields, :direct_behaviors) || [],
        # Born in the void; the subsequent EntityMoved sets the room.
        room_id: nil,
        # Feature 019 — Real Stats. Frozen from the blueprint at spawn; current
        # hp/mana start at max. Fallbacks cover any pre-feature field map.
        str: fval(fields, :str) || 12,
        dex: fval(fields, :dex) || 12,
        con: fval(fields, :con) || 12,
        int: fval(fields, :int) || 12,
        wis: fval(fields, :wis) || 12,
        cha: fval(fields, :cha) || 12,
        level: fval(fields, :level) || 1,
        hp: fval(fields, :hp) || fval(fields, :max_hp) || 10,
        max_hp: fval(fields, :max_hp) || 10,
        mana: fval(fields, :mana) || fval(fields, :max_mana) || 10,
        max_mana: fval(fields, :max_mana) || 10
      },
      on_conflict: :nothing,
      conflict_target: :id
    )

    :ok
  end

  defp container_id_string(%ContainerRef{type: :void}), do: nil
  defp container_id_string(%ContainerRef{id: id}) when is_integer(id), do: Integer.to_string(id)
  defp container_id_string(%ContainerRef{id: id}), do: id

  # Read a field tolerant of atom- (in-process) or string-keyed (replayed) maps.
  defp fval(fields, key) when is_atom(key) do
    case Map.fetch(fields, key) do
      {:ok, v} -> v
      :error -> Map.get(fields, Atom.to_string(key))
    end
  end

  # Keep only the editable object fields, normalizing string keys to atoms.
  defp atomize_fields(changed, allowed) do
    Enum.reduce(allowed, %{}, fn field, acc ->
      cond do
        Map.has_key?(changed, field) ->
          Map.put(acc, field, Map.get(changed, field))

        Map.has_key?(changed, Atom.to_string(field)) ->
          Map.put(acc, field, Map.get(changed, Atom.to_string(field)))

        true ->
          acc
      end
    end)
  end

  defp norm_kind(k) when k in [:object, :npc], do: k
  defp norm_kind("object"), do: :object
  defp norm_kind("npc"), do: :npc

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
