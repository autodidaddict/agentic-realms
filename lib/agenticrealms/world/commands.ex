defmodule AgenticRealms.World.Commands do
  @moduledoc """
  Write-side facade for the world. Wraps Commanded dispatches with
  pre-dispatch read-model validation so the LiveView only has to deal with
  one set of `{:ok, ...} | {:error, atom}` shapes.

  Commands implemented so far:

    * `spawn/2` — Phase 4 (US1)
    * `move/2`  — Phase 5 (US2)
    * `take/2`  — Phase 6 (US3)
    * `drop/2`  — Phase 6 (US3)
  """

  import Ecto.Query

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp

  alias AgenticRealms.World.Commands.{
    SpawnPlayer,
    MovePlayer,
    TakeObject,
    DropObject,
    SpawnNPCClone,
    CreateRegion,
    CreateRoom,
    AddExit,
    RecordRoomDiscovery,
    AcceptQuest,
    FinalizeQuest
  }

  alias AgenticRealms.World.Direction
  alias AgenticRealms.World.Exits.Validator, as: ExitsValidator
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Quests
  alias AgenticRealms.World.Schemas.{Exit, Room, Region, NPCBlueprint, QuestInstance, Object}

  @doc """
  Spawn a player into the starting room if (and only if) they have no
  current room yet. Idempotent for already-spawned players.
  """
  @spec spawn(integer(), String.t()) ::
          {:ok, :spawned | :already_spawned} | {:error, term()}
  def spawn(player_id, starting_room_id)
      when is_integer(player_id) and is_binary(starting_room_id) do
    case Queries.current_room_of(player_id) do
      {:ok, _room_id} ->
        {:ok, :already_spawned}

      {:error, :no_current_room} ->
        case WorldApp.dispatch(
               %SpawnPlayer{
                 player_id: player_id,
                 starting_room_id: starting_room_id
               },
               consistency: :strong
             ) do
          :ok -> {:ok, :spawned}
          {:error, _} = err -> err
        end
    end
  end

  @doc """
  Move the player one step in the given direction.

  Returns `{:ok, to_room_id}` on success; `{:error, :no_exit_in_direction}`
  when the player's current room has no exit in that direction (FR-007);
  `{:error, :no_current_room}` if the player has never spawned.
  """
  @spec move(integer(), atom()) ::
          {:ok, String.t()}
          | {:error, :no_current_room | :no_exit_in_direction | term()}
  def move(player_id, direction)
      when is_integer(player_id) and is_atom(direction) do
    with {:ok, from_room_id} <- Queries.current_room_of(player_id),
         {:ok, to_room_id} <- resolve_exit(from_room_id, direction) do
      case WorldApp.dispatch(
             %MovePlayer{
               player_id: player_id,
               from_room_id: from_room_id,
               to_room_id: to_room_id,
               direction: direction
             },
             consistency: :strong
           ) do
        :ok -> {:ok, to_room_id}
        {:error, _} = err -> err
      end
    end
  end

  @doc """
  Take an object named `name` from the player's current room.

  Pre-dispatch validation (read-model): the player has a current room,
  the room contains exactly one object matching `name`, and that object
  is not fixed (FR-010, FR-011, FR-024).

  Aggregate validation: the object is still in the room when the command
  is processed (race-loser path for the FR-011 / Q1 clarification).

  Returns `{:ok, %{object_id, object_name}}` on success.
  """
  @spec take(integer(), String.t()) ::
          {:ok, %{object_id: String.t(), object_name: String.t()}}
          | {:error,
             :no_current_room
             | :no_such_object
             | :ambiguous
             | :object_is_fixed
             | :object_not_in_room
             | term()}
  def take(player_id, name) when is_integer(player_id) and is_binary(name) do
    with {:ok, room_id} <- Queries.current_room_of(player_id) do
      case Queries.resolve_object_in_room(room_id, player_id, name) do
        {:ok, object_id} ->
          do_take(room_id, player_id, object_id)

        {:error, :no_such_object} ->
          # Feature 007 FR-015: fall through to NPC scope. If an NPC matches,
          # refuse via the existing :object_is_fixed path (the LiveView
          # renders "You can't take that.").
          case Queries.resolve_npc_in_room(room_id, name) do
            {:ok, _npc_id} -> {:error, :object_is_fixed}
            {:error, :no_such_npc} -> {:error, :no_such_object}
            {:error, :ambiguous} -> {:error, :ambiguous}
          end

        {:error, _} = err ->
          err
      end
    end
  end

  defp do_take(room_id, player_id, object_id) do
    with {:ok, false} <- check_not_fixed(object_id),
         object_name <- name_of(object_id),
         :ok <-
           WorldApp.dispatch(
             %TakeObject{
               room_id: room_id,
               player_id: player_id,
               object_id: object_id
             },
             consistency: :strong
           ) do
      {:ok, %{object_id: object_id, object_name: object_name}}
    else
      {:ok, true} -> {:error, :object_is_fixed}
      {:error, _} = err -> err
    end
  end

  @doc """
  Drop an object named `name` from the player's inventory into their
  current room.
  """
  @spec drop(integer(), String.t()) ::
          {:ok, %{object_id: String.t(), object_name: String.t()}}
          | {:error,
             :no_current_room
             | :no_such_object
             | :ambiguous
             | :not_in_inventory
             | term()}
  def drop(player_id, name) when is_integer(player_id) and is_binary(name) do
    with {:ok, room_id} <- Queries.current_room_of(player_id),
         {:ok, object_id} <- resolve_in_inventory(player_id, name),
         object_name <- name_of(object_id),
         :ok <-
           WorldApp.dispatch(
             %DropObject{
               room_id: room_id,
               player_id: player_id,
               object_id: object_id
             },
             consistency: :strong
           ) do
      {:ok, %{object_id: object_id, object_name: object_name}}
    end
  end

  # --- helpers ------------------------------------------------------------

  defp check_not_fixed(object_id) do
    case Queries.object_fixed?(object_id) do
      {:ok, fixed} -> {:ok, fixed}
      {:error, _} = err -> err
    end
  end

  defp resolve_in_inventory(player_id, name) do
    case Queries.resolve_object_in_inventory(player_id, name) do
      {:ok, _} = ok -> ok
      {:error, :no_such_object} -> {:error, :not_in_inventory}
      other -> other
    end
  end

  defp name_of(object_id) do
    case Repo.get(AgenticRealms.World.Schemas.Object, object_id) do
      nil -> "something"
      %{name: name} -> name
    end
  end

  defp resolve_exit(from_room_id, direction) do
    dir_str = Direction.to_string(direction)

    case Repo.one(
           from(e in Exit,
             where: e.source_room_id == ^from_room_id and e.direction == ^dir_str,
             select: e.target_room_id
           )
         ) do
      nil -> {:error, :no_exit_in_direction}
      target -> {:ok, target}
    end
  end

  # --- NPC blueprint cloning (feature 008) --------------------------------

  @doc """
  Spawn a clone of `blueprint_id` into `room_id` with the given `clone_id`.

  Pre-dispatch validation:
    * blueprint exists (`:blueprint_not_found`)
    * room exists (`:room_not_found`)
    * no other clone in this room shares the blueprint's display name
      (`:clone_name_taken_in_room` — preserves feature 007 FR-001a)

  On success, dispatches `SpawnNPCClone` to the blueprint aggregate which
  emits `NPCClonedFromBlueprint` with the aggregate's current data
  materialized into the event (full-copy at dispatch time). Returns
  `{:ok, %{clone_id, serial}}` after re-querying the freshly-projected
  clone.

  See `specs/008-npc-blueprints/contracts/commands.md`.
  """
  @spec spawn_npc_clone(String.t(), String.t(), String.t()) ::
          {:ok, %{clone_id: String.t(), serial: integer()}}
          | {:error,
             :blueprint_not_found
             | :room_not_found
             | :clone_name_taken_in_room
             | :clone_id_already_used
             | term()}
  def spawn_npc_clone(blueprint_id, room_id, clone_id)
      when is_binary(blueprint_id) and is_binary(room_id) and is_binary(clone_id) do
    with {:ok, blueprint} <- Queries.get_npc_blueprint(blueprint_id) |> remap_blueprint_error(),
         :ok <- check_room_exists(room_id),
         :ok <- check_no_clone_name_collision(room_id, blueprint.name),
         :ok <-
           WorldApp.dispatch(
             %SpawnNPCClone{
               blueprint_id: blueprint_id,
               clone_id: clone_id,
               room_id: room_id
             },
             consistency: :strong
           ),
         {:ok, clone} <- Queries.get_npc_clone(clone_id) do
      {:ok, %{clone_id: clone_id, serial: clone.serial}}
    end
  end

  defp remap_blueprint_error({:ok, _} = ok), do: ok
  defp remap_blueprint_error({:error, :no_such_blueprint}), do: {:error, :blueprint_not_found}

  defp check_room_exists(room_id) do
    case Repo.get(Room, room_id) do
      %Room{} -> :ok
      nil -> {:error, :room_not_found}
    end
  end

  defp check_no_clone_name_collision(room_id, name) do
    case Queries.find_clone_in_room_by_name(room_id, name) do
      {:ok, _clone} -> {:error, :clone_name_taken_in_room}
      {:error, :no_such_clone} -> :ok
    end
  end

  # --- Region authoring (feature 012) -------------------------------------

  @doc """
  Create a new region with the given `region_id` and friendly display
  `name`. Pre-dispatch validation: the name is not already in use in the
  read model.

  Dispatches with `consistency: :strong` so the seed (and any subsequent
  `CreateRoom` referencing the new region) can rely on the read-model row
  being present immediately after this returns.
  """
  @spec create_region(String.t(), String.t()) ::
          :ok | {:error, :region_name_taken | term()}
  def create_region(region_id, name) when is_binary(region_id) and is_binary(name) do
    with :ok <- check_region_name_unique(name) do
      WorldApp.dispatch(
        %CreateRegion{region_id: region_id, name: name},
        consistency: :strong
      )
    end
  end

  defp check_region_name_unique(name) do
    case Repo.one(from(r in Region, where: r.name == ^name, select: r.id, limit: 1)) do
      nil -> :ok
      _ -> {:error, :region_name_taken}
    end
  end

  # --- Room authoring (feature 012) ---------------------------------------

  @doc """
  Create a room with map metadata. `opts` may include `:behaviors` (default
  `[]`), `:map_visible` (default `true`), `:elevation` (default `0`),
  `:map_x` and `:map_y` (both default `nil`, meaning off-map).

  Pre-dispatch validation:
    * region exists in the read model (`:region_not_found`)
    * `(:map_x, :map_y)` are both nil OR both integers (`:coords_must_be_pair`)
    * if coords are set, no existing room at `(region_id, elevation, map_x, map_y)`
      (`:coord_taken` — anticipates the partial unique index with a friendly error)
    * elevation is an integer
  """
  @spec create_room(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          :ok
          | {:error,
             :region_not_found
             | :coords_must_be_pair
             | :coord_taken
             | :elevation_must_be_integer
             | term()}
  def create_room(room_id, name, description, region_id, opts \\ [])
      when is_binary(room_id) and is_binary(name) and is_binary(description) and
             is_binary(region_id) do
    behaviors = Keyword.get(opts, :behaviors, [])
    map_visible = Keyword.get(opts, :map_visible, true)
    elevation = Keyword.get(opts, :elevation, 0)
    map_x = Keyword.get(opts, :map_x)
    map_y = Keyword.get(opts, :map_y)

    with :ok <- check_region_exists(region_id),
         :ok <- check_coords_pair(map_x, map_y),
         :ok <- check_elevation_integer(elevation),
         :ok <- check_coord_not_taken(region_id, elevation, map_x, map_y) do
      WorldApp.dispatch(
        %CreateRoom{
          room_id: room_id,
          name: name,
          description: description,
          region_id: region_id,
          behaviors: behaviors,
          map_visible: map_visible,
          elevation: elevation,
          map_x: map_x,
          map_y: map_y
        },
        consistency: :strong
      )
    end
  end

  @doc """
  Add a directional exit from `source_room_id` to `target_room_id`.
  Validates direction-coordinate consistency per FR-024 via
  `Exits.Validator`. Off-map rooms (either side missing coords) skip the
  geometric check — supports wormhole-like patterns.
  """
  @spec add_exit(String.t(), atom(), String.t()) ::
          :ok
          | {:error,
             :source_room_not_found
             | :target_room_not_found
             | {:exit_geometry_violation, atom()}
             | term()}
  def add_exit(source_room_id, direction, target_room_id)
      when is_binary(source_room_id) and is_atom(direction) and is_binary(target_room_id) do
    with {:ok, source} <- fetch_room(source_room_id, :source_room_not_found),
         {:ok, target} <- fetch_room(target_room_id, :target_room_not_found),
         :ok <- ExitsValidator.consistent?(direction, source, target) do
      WorldApp.dispatch(%AddExit{
        room_id: source_room_id,
        direction: direction,
        target_room_id: target_room_id
      })
    end
  end

  defp check_region_exists(region_id) do
    case Repo.one(from(r in Region, where: r.id == ^region_id, select: r.id, limit: 1)) do
      nil -> {:error, :region_not_found}
      _ -> :ok
    end
  end

  defp check_coords_pair(nil, nil), do: :ok
  defp check_coords_pair(x, y) when is_integer(x) and is_integer(y), do: :ok
  defp check_coords_pair(_, _), do: {:error, :coords_must_be_pair}

  defp check_elevation_integer(e) when is_integer(e), do: :ok
  defp check_elevation_integer(_), do: {:error, :elevation_must_be_integer}

  defp check_coord_not_taken(_region_id, _elevation, nil, nil), do: :ok

  defp check_coord_not_taken(region_id, elevation, map_x, map_y) do
    existing =
      Repo.one(
        from(r in Room,
          where:
            r.region_id == ^region_id and
              r.elevation == ^elevation and
              r.map_x == ^map_x and
              r.map_y == ^map_y,
          select: r.id,
          limit: 1
        )
      )

    case existing do
      nil -> :ok
      _ -> {:error, :coord_taken}
    end
  end

  defp fetch_room(room_id, missing_error) do
    case Repo.get(Room, room_id) do
      %Room{} = r -> {:ok, r}
      nil -> {:error, missing_error}
    end
  end

  # --- Discovery (feature 012) --------------------------------------------

  @doc """
  Dispatches a `RecordRoomDiscovery` command to the World.Player aggregate.
  The aggregate decides whether to emit a `PlayerDiscoveredRoom` event
  (only on first discovery for that room) — the caller MUST NOT pre-check
  the read model.

  This is the ONLY supported way to add a row to `player_discovered_rooms`.
  Direct Repo inserts to that table are forbidden by the project's event-
  sourcing invariant.

  **Eventual consistency.** This dispatch is called from inside the
  `PlayerStateProjector` event handler; a `consistency: :strong` dispatch
  would deadlock waiting for the same projector to acknowledge the
  resulting `PlayerDiscoveredRoom` event. The map's first render after
  spawn may briefly precede the discovery-row projection — that race is
  benign (the renderer just won't draw the room until the next refresh,
  which happens on the next move and on any subsequent UI event).
  """
  @spec record_room_discovery(integer(), String.t()) :: :ok | {:error, term()}
  def record_room_discovery(player_id, room_id)
      when is_integer(player_id) and is_binary(room_id) do
    WorldApp.dispatch(%RecordRoomDiscovery{player_id: player_id, room_id: room_id})
  end

  # --- Quest acceptance (feature 013) -------------------------------------

  @doc """
  Accept the FetchQuest with slug `slug` from `npc_blueprint_id` on behalf
  of `player_id`. Pre-dispatch validation enforces FR-009:

    * `:unknown_npc` — blueprint doesn't exist
    * `:unknown_slug` — slug is not in the NPC's catalog
    * `:already_completed` — this player has already finished this quest
      with this NPC (FR-012, sticky completion)
    * `{:already_active, existing_quest_id}` — this player already has
      this quest in flight with this NPC

  On success, generates a fresh `quest_id`, snapshots the catalog entry
  with instance-scoped quest tags, dispatches `AcceptQuest` to the Quest
  aggregate, and returns `{:ok, quest_id}`. The projector handler for
  `QuestAccepted` then inserts the `quest_instances` row and dispatches
  `PlaceObject` for each criterion's spawn rooms.
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
    case Repo.get(NPCBlueprint, npc_blueprint_id) do
      nil ->
        {:error, :unknown_npc}

      %NPCBlueprint{quests: catalog} ->
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

  # --- Quest progress check (feature 013) ---------------------------------

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

  # --- Quest finalization (feature 013) -----------------------------------

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

      case WorldApp.dispatch(
             %FinalizeQuest{
               quest_id: quest_id,
               consumed_object_ids: plan.consumed_object_ids,
               reward_object_id: reward_object_id,
               reward_name: reward_name,
               reward_description: reward_description,
               remaining_quest_object_ids: plan.remaining_quest_object_ids,
               completed_at: completed_at
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

  defp build_finalize_plan(%QuestInstance{
         id: qid,
         player_id: pid,
         definition_snapshot: snapshot
       }) do
    # All quest-scoped objects for this instance, partitioned by where
    # they currently sit. `in_inventory` are the candidates for
    # consumption; everything else needs cleanup.
    all_objects =
      from(o in Object, where: o.quest_instance_id == ^qid)
      |> Repo.all()

    {in_inventory, elsewhere} =
      Enum.split_with(all_objects, fn o ->
        o.player_id == pid and is_nil(o.room_id)
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
