defmodule AgenticRealms.World.Ticks.Scope do
  @moduledoc """
  Pure (DB-bound on `compute/1`; pure list ops otherwise) computation of
  the in-scope tick-behavior set for a room (feature 011).

  An "in-scope" entry is one tick-triggered behavior on one of four
  authoring surfaces:

    * the room itself (`Room.behaviors`)
    * an NPC clone currently in the room (`NPCClone.behaviors`)
    * an object currently in the room (`Object.behaviors`)
    * an object currently held by a player whose `current_room_id` is
      this room (`Object.behaviors` via inventory)

  See `specs/011-room-tick-timers/contracts/scope.md`.
  """

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.{NPCClone, Object, Room}

  @type behavior_entry :: %{
          target_kind: :room | :npc | :object,
          target_id: String.t(),
          behavior_index: non_neg_integer(),
          interval_ms: pos_integer(),
          actions: [map()],
          key: {atom(), String.t(), non_neg_integer()},
          speaker_ctx: term()
        }

  @doc """
  Compute the full in-scope tick-behavior set for `room_id`. Sorted per
  FR-008a (room → npc → object; within a kind by target_id; within a single
  target by authored behavior_index).
  """
  @spec compute(room_id :: String.t()) :: [behavior_entry()]
  def compute(room_id) when is_binary(room_id) do
    (room_entries(room_id) ++
       npc_entries(room_id) ++
       in_room_object_entries(room_id) ++
       carried_object_entries(room_id))
    |> sort_per_fr008a()
  end

  # --- Incremental updates -----------------------------------------------

  @spec add_npc([behavior_entry()], npc_id :: String.t()) :: [behavior_entry()]
  def add_npc(entries, npc_id) do
    case Repo.get(NPCClone, npc_id) do
      nil ->
        entries

      %NPCClone{} = clone ->
        new = npc_entries_for_clone(clone)
        (entries ++ new) |> dedup() |> sort_per_fr008a()
    end
  end

  @spec remove_npc([behavior_entry()], npc_id :: String.t()) :: [behavior_entry()]
  def remove_npc(entries, npc_id) do
    Enum.reject(entries, fn e -> e.target_kind == :npc and e.target_id == npc_id end)
  end

  @spec add_carried_object([behavior_entry()], player_id :: integer(), object_id :: String.t()) ::
          [behavior_entry()]
  def add_carried_object(entries, _player_id, object_id) do
    case Repo.get(Object, object_id) do
      nil ->
        entries

      %Object{} = obj ->
        new = object_entries_for(obj)
        (entries ++ new) |> dedup() |> sort_per_fr008a()
    end
  end

  @spec remove_carried_object(
          [behavior_entry()],
          player_id :: integer(),
          object_id :: String.t()
        ) :: [behavior_entry()]
  def remove_carried_object(entries, _player_id, object_id) do
    Enum.reject(entries, fn e -> e.target_kind == :object and e.target_id == object_id end)
  end

  @spec add_in_room_object([behavior_entry()], object_id :: String.t()) :: [behavior_entry()]
  def add_in_room_object(entries, object_id) do
    add_carried_object(entries, nil, object_id)
  end

  @spec remove_in_room_object([behavior_entry()], object_id :: String.t()) :: [behavior_entry()]
  def remove_in_room_object(entries, object_id) do
    remove_carried_object(entries, nil, object_id)
  end

  # --- Internal builders -------------------------------------------------

  defp room_entries(room_id) do
    case Repo.get(Room, room_id) do
      nil ->
        []

      %Room{behaviors: behaviors} ->
        behaviors
        |> filter_tick_behaviors()
        |> Enum.with_index()
        |> Enum.map(fn {behavior, idx} ->
          build_entry(:room, room_id, idx, behavior, {:room, room_id})
        end)
    end
  end

  defp npc_entries(room_id) do
    Queries.list_npc_clones_in_room_with_behaviors(room_id)
    |> Enum.flat_map(&npc_entries_for_clone_data/1)
  end

  # The Queries helper returns plain maps (id, name, behaviors).
  defp npc_entries_for_clone_data(%{id: id, name: name, behaviors: behaviors}) do
    (behaviors || [])
    |> filter_tick_behaviors()
    |> Enum.with_index()
    |> Enum.map(fn {behavior, idx} ->
      speaker_ctx = {:npc_clone, %{name: name, id: id}}
      build_entry(:npc, id, idx, behavior, speaker_ctx)
    end)
  end

  # add_npc/2 looks up the full NPCClone struct from Repo; this clause
  # accepts that shape too for incremental updates.
  defp npc_entries_for_clone(%NPCClone{} = clone) do
    npc_entries_for_clone_data(%{
      id: clone.id,
      name: clone.name,
      behaviors: clone.behaviors
    })
  end

  # The query returns plain maps (id, name, short_description) — not full
  # Object structs. Hydrate the Object struct before building entries so
  # we can read `behaviors`.
  defp in_room_object_entries(room_id) do
    Queries.list_objects_in_room(room_id)
    |> Enum.flat_map(fn %{id: object_id} ->
      case Repo.get(Object, object_id) do
        nil -> []
        %Object{} = obj -> object_entries_for(obj)
      end
    end)
  end

  defp carried_object_entries(room_id) do
    Queries.list_carried_objects_in_room(room_id)
    |> Enum.flat_map(&object_entries_for/1)
  end

  defp object_entries_for(%Object{} = obj) do
    behaviors = obj.behaviors || []

    behaviors
    |> filter_tick_behaviors()
    |> Enum.with_index()
    |> Enum.map(fn {behavior, idx} ->
      speaker_ctx = {:object, %{name: obj.name, id: obj.id}}
      build_entry(:object, obj.id, idx, behavior, speaker_ctx)
    end)
  end

  defp build_entry(kind, target_id, idx, behavior, speaker_ctx) do
    %{
      target_kind: kind,
      target_id: target_id,
      behavior_index: idx,
      interval_ms: interval_ms_of(behavior),
      actions: actions_of(behavior),
      key: {kind, target_id, idx},
      speaker_ctx: speaker_ctx
    }
  end

  defp filter_tick_behaviors(behaviors) do
    Enum.filter(behaviors, fn b ->
      Map.get(b, "trigger") == "tick" or Map.get(b, :trigger) == "tick"
    end)
  end

  defp interval_ms_of(behavior) do
    Map.get(behavior, "interval_ms") || Map.get(behavior, :interval_ms)
  end

  defp actions_of(behavior) do
    Map.get(behavior, "actions") || Map.get(behavior, :actions) || []
  end

  # Stable FR-008a sort. Tuple key: kind_rank, target_id, behavior_index.
  defp sort_per_fr008a(entries) do
    Enum.sort_by(entries, fn e ->
      {kind_rank(e.target_kind), e.target_id, e.behavior_index}
    end)
  end

  defp kind_rank(:room), do: 0
  defp kind_rank(:npc), do: 1
  defp kind_rank(:object), do: 2

  defp dedup(entries) do
    entries
    |> Enum.uniq_by(& &1.key)
  end
end
