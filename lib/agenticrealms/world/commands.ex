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
    SpawnNPCClone
  }

  alias AgenticRealms.World.Direction
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.{Exit, Room}

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
      case Queries.resolve_object_in_room(room_id, name) do
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
end
