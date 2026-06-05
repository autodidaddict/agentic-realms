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

  alias AgenticRealms.Accounts
  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp

  alias AgenticRealms.World.Commands.{
    SpawnPlayer,
    MovePlayer,
    CreateRegion,
    CreateRoom,
    AddExit,
    RecordRoomDiscovery,
    AcceptQuest,
    FinalizeQuest,
    CreateBlueprint,
    EditBlueprint,
    CloneEntity,
    MoveEntity,
    EditEntity
  }

  alias AgenticRealms.World.ContainerRef

  alias AgenticRealms.World.Blueprint.Slug

  alias AgenticRealms.World.Direction
  alias AgenticRealms.World.Exits.Validator, as: ExitsValidator
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Quests
  alias AgenticRealms.World.Toolsets
  alias AgenticRealms.World.Schemas.{Exit, Room, Region, Blueprint, QuestInstance, Object}

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

  # ──────────────────────────────────────────────────────────────────────
  # Feature 016 — entity lifecycle world service (clone / move / clone_into)
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Clone a world entity into existence (in the void). Mints a fresh id, or
  use the 3-arity form to supply a deterministic id (replay-safe; a re-clone
  of an existing entity is treated as success).
  """
  @spec clone_entity(:object | :npc, map()) :: {:ok, String.t()} | {:error, atom()}
  def clone_entity(kind, fields), do: clone_entity(kind, Ecto.UUID.generate(), fields)

  @spec clone_entity(:object | :npc, String.t(), map()) :: {:ok, String.t()} | {:error, atom()}
  def clone_entity(kind, entity_id, fields)
      when is_binary(entity_id) and is_map(fields) do
    case WorldApp.dispatch(
           %CloneEntity{entity_id: entity_id, kind: kind, fields: fields},
           consistency: :strong
         ) do
      :ok -> {:ok, entity_id}
      {:error, :already_exists} -> {:ok, entity_id}
      {:error, _} = err -> err
    end
  end

  @doc """
  Move an entity into `to`, asserting it is currently in `expected_from`.
  A `:container_conflict` means the entity is no longer where the caller
  resolved it (e.g. already taken).
  """
  @spec move_entity(String.t(), ContainerRef.t(), ContainerRef.t(), atom()) ::
          :ok | {:error, atom()}
  def move_entity(entity_id, %ContainerRef{} = expected_from, %ContainerRef{} = to, cause)
      when is_binary(entity_id) do
    with :ok <- ensure_container_exists(to) do
      WorldApp.dispatch(
        %MoveEntity{entity_id: entity_id, expected_from: expected_from, to: to, cause: cause},
        consistency: :strong
      )
    end
  end

  @doc "Clone an entity and immediately move it into `to` (the void → target wrapper)."
  @spec clone_into(:object | :npc, map(), ContainerRef.t(), atom()) ::
          {:ok, String.t()} | {:error, atom()}
  def clone_into(kind, fields, %ContainerRef{} = to, cause),
    do: clone_into(kind, Ecto.UUID.generate(), fields, to, cause)

  @spec clone_into(:object | :npc, String.t(), map(), ContainerRef.t(), atom()) ::
          {:ok, String.t()} | {:error, atom()}
  def clone_into(kind, entity_id, fields, %ContainerRef{} = to, cause) do
    with {:ok, id} <- clone_entity(kind, entity_id, fields),
         :ok <- move_entity(id, ContainerRef.void(), to, cause) do
      {:ok, id}
    end
  end

  defp ensure_container_exists(%ContainerRef{type: :void}), do: :ok

  defp ensure_container_exists(%ContainerRef{type: :room, id: rid}) do
    case Repo.get(Room, rid) do
      %Room{} -> :ok
      nil -> {:error, :room_not_found}
    end
  end

  # Players exist by account FK; NPC-inventory is defined-but-dormant (R8) —
  # accept both at the service boundary.
  defp ensure_container_exists(%ContainerRef{type: :player}), do: :ok
  defp ensure_container_exists(%ContainerRef{type: :npc}), do: :ok

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
           move_entity(
             object_id,
             ContainerRef.room(room_id),
             ContainerRef.player(player_id),
             :taken
           ) do
      {:ok, %{object_id: object_id, object_name: object_name}}
    else
      {:ok, true} -> {:error, :object_is_fixed}
      # The object moved out of the room between resolve and dispatch (e.g.
      # another player took it first) — preserve the legacy race-loser error.
      {:error, :container_conflict} -> {:error, :object_not_in_room}
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
           move_entity(
             object_id,
             ContainerRef.player(player_id),
             ContainerRef.room(room_id),
             :dropped
           ) do
      {:ok, %{object_id: object_id, object_name: object_name}}
    else
      {:error, :container_conflict} -> {:error, :not_in_inventory}
      {:error, _} = err -> err
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

  On success, clones the NPC into existence and moves it into the room via
  the entity lifecycle (`clone_into(:npc, …)`), with the blueprint's current
  data (incl. its `blueprint_id` reference, behaviors and lore) copied into
  the `EntityCloned` payload (full-copy at dispatch time). Returns
  `{:ok, %{clone_id, serial}}`.

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
    # Feature 016 — an NPC clone is cloned into existence (a full copy of the
    # blueprint's current data, incl. its blueprint_id reference, serial,
    # behaviors and lore) and moved into the room via the entity lifecycle.
    with {:ok, blueprint} <- fetch_npc_blueprint(blueprint_id),
         :ok <- check_room_exists(room_id),
         :ok <- check_no_clone_name_collision(room_id, blueprint.name) do
      serial = next_npc_serial(blueprint_id)

      fields = %{
        blueprint_id: blueprint_id,
        serial: serial,
        name: blueprint.name,
        short_description: blueprint.short_description,
        long_description: blueprint.long_description,
        behaviors: blueprint.behaviors || [],
        lore: blueprint.lore || ""
      }

      case clone_into(:npc, clone_id, fields, ContainerRef.room(room_id), :spawned) do
        {:ok, _} -> {:ok, %{clone_id: clone_id, serial: serial}}
        {:error, _} = err -> err
      end
    end
  end

  defp fetch_npc_blueprint(blueprint_id) do
    case Repo.get(Blueprint, blueprint_id) do
      nil -> {:error, :blueprint_not_found}
      %Blueprint{kind: "npc"} = bp -> {:ok, bp}
      # A slug that resolves to an object blueprint is not a valid NPC source.
      %Blueprint{} -> {:error, :blueprint_not_found}
    end
  end

  defp next_npc_serial(blueprint_id) do
    from(c in AgenticRealms.World.Schemas.NPCClone,
      where: c.blueprint_id == ^blueprint_id,
      select: max(c.serial)
    )
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

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
  `QuestAccepted` then inserts the `quest_instances` row and clones a
  quest-scoped item into each criterion's spawn rooms via the entity
  lifecycle (feature 016).
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

  # ──────────────────────────────────────────────────────────────────────
  # Feature 014 — Object Blueprint authoring
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Author a new Object Blueprint.

  Wrapper performs the FR-WIZ-5 authorization check, FR-007a slug-shape
  validation, and FR-007b slug-uniqueness pre-check before dispatching
  to the `ObjectBlueprint` aggregate.

  Returns `{:ok, blueprint_id}` on success.
  Refusals:
    * `{:error, :not_a_wizard}` — caller's `is_wizard` is false.
    * `{:error, :unknown_player}` — caller's player_id is unknown.
    * `{:error, :invalid_slug}` — slug fails the regex / length rules.
    * `{:error, :slug_already_exists}` — slug collides with an existing row.
    * `{:error, :name_required}` / `:short_description_required` /
      `:long_description_required` — content field missing.
  """
  @spec create_object_blueprint(
          %{
            required(:wizard_id) => integer(),
            required(:blueprint_id) => String.t(),
            required(:name) => String.t(),
            required(:short_description) => String.t(),
            required(:long_description) => String.t(),
            optional(:fixed) => boolean()
          },
          keyword()
        ) :: {:ok, String.t()} | {:error, atom()}
  def create_object_blueprint(attrs, _opts \\ []) when is_map(attrs) do
    with :ok <- ensure_wizard(attrs[:wizard_id]),
         :ok <- validate_slug(attrs[:blueprint_id]),
         :ok <- ensure_slug_unused(attrs[:blueprint_id]) do
      cmd = %CreateBlueprint{
        blueprint_id: attrs[:blueprint_id],
        wizard_id: attrs[:wizard_id],
        kind: "object",
        name: attrs[:name],
        short_description: attrs[:short_description],
        long_description: attrs[:long_description],
        fixed: Map.get(attrs, :fixed, false)
      }

      case WorldApp.dispatch(cmd, consistency: :strong) do
        :ok -> {:ok, attrs[:blueprint_id]}
        {:error, _} = err -> err
      end
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Feature 015 — NPC Blueprint authoring
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Author a new NPC Blueprint.

  Mirrors `create_object_blueprint/2`: FR-WIZ-5 authorization, FR-004
  slug-shape + cross-registry uniqueness pre-check, plus NPC-specific
  validation — the direct `behaviors` against the feature-009 vocabulary
  (FR-014) and every referenced `toolset` name against the registry
  (FR-018). Behaviors here are the DIRECT behaviors; the effective set is
  composed (union with toolsets) at spawn time.

  Returns `{:ok, blueprint_id}` on success.
  Refusals:
    * `{:error, :not_a_wizard}` / `{:error, :unknown_player}`.
    * `{:error, :invalid_slug}` / `{:error, :slug_already_exists}`.
    * `{:error, :name_required}` / `:short_description_required` /
      `:long_description_required` — content field missing.
    * `{:error, {:unknown_toolset, name}}` — a referenced toolset is not
      in the registry.
    * `{:error, term()}` — a direct behavior fails feature-009 validation.
  """
  @spec create_npc_blueprint(
          %{
            required(:wizard_id) => integer(),
            required(:blueprint_id) => String.t(),
            required(:name) => String.t(),
            required(:short_description) => String.t(),
            required(:long_description) => String.t(),
            optional(:lore) => String.t(),
            optional(:fixed) => boolean(),
            optional(:behaviors) => [map()],
            optional(:toolsets) => [String.t()]
          },
          keyword()
        ) :: {:ok, String.t()} | {:error, atom()} | {:error, {:unknown_toolset, String.t()}}
  def create_npc_blueprint(attrs, _opts \\ []) when is_map(attrs) do
    behaviors = Map.get(attrs, :behaviors, []) || []
    toolsets = Map.get(attrs, :toolsets, []) || []

    with :ok <- ensure_wizard(attrs[:wizard_id]),
         :ok <- validate_slug(attrs[:blueprint_id]),
         :ok <- ensure_slug_unused(attrs[:blueprint_id]),
         :ok <- Toolsets.validate_behaviors(behaviors),
         :ok <- Toolsets.all_exist?(toolsets) do
      cmd = %CreateBlueprint{
        blueprint_id: attrs[:blueprint_id],
        wizard_id: attrs[:wizard_id],
        kind: "npc",
        name: attrs[:name],
        short_description: attrs[:short_description],
        long_description: attrs[:long_description],
        lore: Map.get(attrs, :lore, "") || "",
        behaviors: behaviors,
        fixed: Map.get(attrs, :fixed, false),
        toolsets: toolsets
      }

      case WorldApp.dispatch(cmd, consistency: :strong) do
        :ok -> {:ok, attrs[:blueprint_id]}
        {:error, _} = err -> err
      end
    end
  end

  @doc """
  Spawn a clone of an Object Blueprint into a room.

  Wrapper performs the FR-WIZ-5 authorization check, resolves the
  blueprint payload from the read model (the aggregate cannot — by
  design — see FR-013), stamps the denormalized fields into the
  command, and dispatches.

  Returns `{:ok, object_id}` on success.
  Refusals:
    * `{:error, :not_a_wizard}` — caller's `is_wizard` is false.
    * `{:error, :unknown_player}` — caller's player_id is unknown.
    * `{:error, :unknown_blueprint}` — `blueprint_id` does not exist.
    * `{:error, :object_already_in_room}` — defensive; should not occur
      for a freshly-generated UUID.
  """
  @spec spawn_object_from_blueprint(
          wizard_id :: integer(),
          blueprint_id :: String.t(),
          room_id :: String.t()
        ) :: {:ok, String.t()} | {:error, atom()}
  def spawn_object_from_blueprint(wizard_id, blueprint_id, room_id)
      when is_integer(wizard_id) and is_binary(blueprint_id) and is_binary(room_id) do
    with :ok <- ensure_wizard(wizard_id),
         {:ok, blueprint} <- fetch_blueprint(blueprint_id) do
      clone_into(
        :object,
        %{
          name: blueprint.name,
          short_description: blueprint.short_description,
          long_description: blueprint.long_description,
          fixed: blueprint.fixed,
          behaviors: [],
          quest_player_id: nil,
          quest_instance_id: nil
        },
        ContainerRef.room(room_id),
        :spawned
      )
    end
  end

  defp fetch_blueprint(blueprint_id) do
    case Repo.get(Blueprint, blueprint_id) do
      nil -> {:error, :unknown_blueprint}
      %Blueprint{kind: "object"} = bp -> {:ok, bp}
      # A slug that resolves to an npc blueprint is not a valid object source.
      %Blueprint{} -> {:error, :unknown_blueprint}
    end
  end

  @doc """
  Spawn a freeform Object into a room — no Object Blueprint involvement,
  no registry change. The wizard's authored payload is cloned into the
  room via the entity lifecycle (`clone_into(:object, …)`, feature 016).

  Returns `{:ok, object_id}` on success.
  Refusals:
    * `{:error, :not_a_wizard}` — caller's `is_wizard` is false.
    * `{:error, :unknown_player}` — caller's player_id is unknown.
    * `{:error, :name_required}` / `:short_description_required` /
      `:long_description_required` — required content field missing.
  """
  @spec spawn_object_freeform(
          wizard_id :: integer(),
          room_id :: String.t(),
          attrs :: %{
            required(:name) => String.t(),
            required(:short_description) => String.t(),
            required(:long_description) => String.t(),
            optional(:fixed) => boolean()
          }
        ) :: {:ok, String.t()} | {:error, atom()}
  def spawn_object_freeform(wizard_id, room_id, attrs)
      when is_integer(wizard_id) and is_binary(room_id) and is_map(attrs) do
    with :ok <- ensure_wizard(wizard_id),
         :ok <- validate_object_attrs(attrs) do
      clone_into(
        :object,
        %{
          name: attrs[:name],
          short_description: attrs[:short_description],
          long_description: attrs[:long_description],
          fixed: Map.get(attrs, :fixed, false),
          behaviors: [],
          quest_player_id: nil,
          quest_instance_id: nil
        },
        ContainerRef.room(room_id),
        :spawned
      )
    end
  end

  @doc """
  One-shot extract-essence — read a world Object's denormalized fields
  and persist a new Object Blueprint at `revision: 1` populated with a
  wholesale copy of those fields (FR-016 / FR-018). The source Object
  is NOT modified.

  Returns `{:ok, blueprint_id}` on success.
  Refusals:
    * `{:error, :not_a_wizard}` / `{:error, :unknown_player}`.
    * `{:error, :unknown_object}` — `source_object_id` not in `world_objects`.
    * `{:error, :invalid_slug}` / `{:error, :slug_already_exists}` —
      same as `create_object_blueprint/2`.

  Intended for use from `iex` or test setup; the LiveView path
  (`handle_event("extract_essence", ...)`) instead populates the
  Interpreted Data card and lets the wizard refine the draft before
  dispatching via the normal `commit_blueprint_draft` flow.
  """
  @spec extract_object_essence(
          wizard_id :: integer(),
          source_object_id :: String.t(),
          proposed_slug :: String.t()
        ) :: {:ok, String.t()} | {:error, atom()}
  def extract_object_essence(wizard_id, source_object_id, proposed_slug)
      when is_integer(wizard_id) and is_binary(source_object_id) and is_binary(proposed_slug) do
    with :ok <- ensure_wizard(wizard_id),
         {:ok, object} <- fetch_object(source_object_id) do
      create_object_blueprint(%{
        wizard_id: wizard_id,
        blueprint_id: proposed_slug,
        name: object.name,
        short_description: object.short_description,
        long_description: object.long_description,
        fixed: object.fixed
      })
    end
  end

  defp fetch_object(object_id) do
    case Repo.get(AgenticRealms.World.Schemas.Object, object_id) do
      nil ->
        {:error, :unknown_object}

      # Wizards cannot extract or edit quest-scoped objects in milestone
      # 1 — these belong to a specific player. The Things-in-this-room
      # panel already filters them out via
      # `Queries.list_objects_in_room_for_wizard/1`; this is the
      # defense-in-depth at the Commands wrapper boundary so a crafted
      # client event or iex caller can't bypass.
      %{quest_player_id: pid} when not is_nil(pid) ->
        {:error, :unknown_object}

      o ->
        {:ok, o}
    end
  end

  @edit_object_blueprint_fields ~w(name short_description long_description fixed)a

  @doc """
  Edit an existing Object Blueprint. `expected_revision` MUST equal the
  blueprint's current revision (FR-020a). On stale revision the wrapper
  returns `{:error, :stale_revision, current_revision: N}` so the
  LiveView can reload the form with the latest values.

  Returns `{:ok, new_revision}` on a field-changing commit. Returns
  `{:ok, :no_change}` when every field in `fields_changed` already
  equals the current state (FR-008 — no revision bump for no-op).

  Refusals:
    * `{:error, :not_a_wizard}` / `{:error, :unknown_player}`.
    * `{:error, :unknown_blueprint}`.
    * `{:error, :invalid_field}` — `fields_changed` contains an
      unrecognized key.
    * `{:error, :stale_revision, current_revision: N}` — optimistic
      lock fired.
  """
  @spec edit_object_blueprint(
          wizard_id :: integer(),
          blueprint_id :: String.t(),
          %{
            required(:expected_revision) => integer(),
            required(:fields_changed) => map()
          }
        ) ::
          {:ok, new_revision :: integer()}
          | {:ok, :no_change}
          | {:error, atom()}
          | {:error, :stale_revision, [current_revision: integer()]}
  def edit_object_blueprint(wizard_id, blueprint_id, params)
      when is_integer(wizard_id) and is_binary(blueprint_id) and is_map(params) do
    with :ok <- ensure_wizard(wizard_id),
         {:ok, blueprint} <- fetch_blueprint(blueprint_id),
         :ok <- validate_edit_fields(params[:fields_changed]) do
      cmd = %EditBlueprint{
        blueprint_id: blueprint_id,
        wizard_id: wizard_id,
        expected_revision: params[:expected_revision],
        fields_changed: params[:fields_changed]
      }

      case WorldApp.dispatch(cmd, consistency: :strong) do
        :ok ->
          # Aggregate accepted but emitted no event (no-op diff) OR
          # accepted and emitted the edit event. Re-read to determine
          # the actual new revision.
          updated = Repo.get(Blueprint, blueprint_id)

          cond do
            updated.revision == blueprint.revision -> {:ok, :no_change}
            true -> {:ok, updated.revision}
          end

        {:error, :stale_revision} ->
          current = Repo.get(Blueprint, blueprint_id)
          {:error, :stale_revision, current_revision: current.revision}

        {:error, _} = err ->
          err
      end
    end
  end

  defp validate_edit_fields(fields) when is_map(fields) do
    if Enum.all?(Map.keys(fields), &(&1 in @edit_object_blueprint_fields)) do
      :ok
    else
      {:error, :invalid_field}
    end
  end

  defp validate_edit_fields(_), do: {:error, :invalid_field}

  @doc """
  Edit a world Object in place. Routes through the Room aggregate that
  currently contains the object; the wrapper looks up the object's
  current `room_id` from the read model so callers don't need to know.

  Returns `{:ok, :updated}` on a field-changing commit, `{:ok, :no_change}`
  on a no-op diff.

  Refusals:
    * `{:error, :not_a_wizard}` / `{:error, :unknown_player}`.
    * `{:error, :unknown_object}` — object_id not in `world_objects`, OR
      object is quest-scoped (wizards do not edit per-player quest items
      in milestone 1).
    * `{:error, :object_not_editable_here}` — object is not currently
      in a room (e.g., carried by a player) OR it is in a different
      room than the wizard's current room. Per `contracts/commands.md`,
      both halves of this clause are part of the contract; the
      same-room enforcement here is the security boundary that the
      LiveView's focus-time pattern match (the UX gate) sits in front
      of.
    * `{:error, :invalid_field}`.
  """
  @spec edit_object(
          wizard_id :: integer(),
          object_id :: String.t(),
          fields_changed :: map()
        ) :: {:ok, :updated | :no_change} | {:error, atom()}
  def edit_object(wizard_id, object_id, fields_changed)
      when is_integer(wizard_id) and is_binary(object_id) and is_map(fields_changed) do
    with :ok <- ensure_wizard(wizard_id),
         {:ok, object} <- fetch_object(object_id),
         :ok <- validate_edit_fields(fields_changed),
         {:ok, room_id} <- ensure_in_room(object),
         :ok <- ensure_wizard_co_located(wizard_id, room_id) do
      diff = only_actual_diff(object, fields_changed)

      cond do
        map_size(diff) == 0 ->
          {:ok, :no_change}

        true ->
          # `room_id` was only used to route to the Room aggregate; entity
          # edits route by entity_id. The co-location check above remains the
          # security boundary (the object must be in the wizard's room).
          _ = room_id

          case WorldApp.dispatch(
                 %EditEntity{entity_id: object_id, fields_changed: diff},
                 consistency: :strong
               ) do
            :ok -> {:ok, :updated}
            {:error, _} = err -> err
          end
      end
    end
  end

  defp ensure_in_room(%{container_type: "room", container_id: rid}) when is_binary(rid),
    do: {:ok, rid}

  defp ensure_in_room(_), do: {:error, :object_not_editable_here}

  # Feature 014 US5 — cross-room defense in depth. The LiveView's
  # `focus_object_for_edit` pattern matches `obj.room_id == ^room_id`
  # at focus time (the UX gate), but the wizard's `:focused_object_edit`
  # assign persists across PlayerMoved, so a focus-then-walk-then-commit
  # sequence would otherwise let the wizard edit an object in a room
  # they're no longer in. Per `contracts/commands.md`, the Commands
  # wrapper IS the security boundary here.
  defp ensure_wizard_co_located(wizard_id, object_room_id) do
    case AgenticRealms.World.Queries.current_room_of(wizard_id) do
      {:ok, ^object_room_id} -> :ok
      _ -> {:error, :object_not_editable_here}
    end
  end

  defp only_actual_diff(object, fields_changed) do
    fields_changed
    |> Enum.reject(fn {k, v} -> Map.get(object, k) == v end)
    |> Map.new()
  end

  defp validate_object_attrs(attrs) do
    cond do
      blank?(attrs[:name]) -> {:error, :name_required}
      blank?(attrs[:short_description]) -> {:error, :short_description_required}
      blank?(attrs[:long_description]) -> {:error, :long_description_required}
      true -> :ok
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(str) when is_binary(str), do: String.trim(str) == ""
  defp blank?(_), do: true

  defp validate_slug(slug) do
    if Slug.valid?(slug), do: :ok, else: {:error, :invalid_slug}
  end

  # FR-004 — a blueprint slug is unique across BOTH the object and NPC
  # registries, so a wizard can never author an object and an NPC under the
  # same id (the unified registry, US8, keys on it).
  # FR-004 — one slug namespace across both kinds (the unified `blueprints`
  # table keys on it), so a wizard can never author an object and an NPC under
  # the same id.
  defp ensure_slug_unused(slug) do
    case Repo.get(Blueprint, slug) do
      nil -> :ok
      _ -> {:error, :slug_already_exists}
    end
  end

  # Feature 014 — wizard authorization gate. Synchronous read of the
  # `players.is_wizard` flag (FR-WIZ-5). Used as the entry guard on every
  # wizard-only command wrapper.
  defp ensure_wizard(player_id) when is_integer(player_id) do
    case Accounts.get_player(player_id) do
      %Accounts.Player{is_wizard: true} -> :ok
      %Accounts.Player{is_wizard: false} -> {:error, :not_a_wizard}
      nil -> {:error, :unknown_player}
    end
  end

  defp ensure_wizard(_), do: {:error, :unknown_player}

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
