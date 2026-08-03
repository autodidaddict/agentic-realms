defmodule AgenticRealms.World.Commands.Entities do
  @moduledoc """
  Write-side facade for the entity lifecycle (feature 016): bringing an entity
  into existence, moving it between containers, removing it, and the two player
  verbs built on those — `take` and `drop`.

  Every movable thing in the world, object or NPC, is an entity here. Split out
  of `AgenticRealms.World.Commands`, which had grown to cover every bounded
  concern in the world behind one module. `Commands` still delegates here, so
  callers are unchanged.
  """

  alias AgenticRealms.Repo
  alias AgenticRealms.World.Application, as: WorldApp
  alias AgenticRealms.World.Commands.{CloneEntity, MoveEntity, RemoveEntity}
  alias AgenticRealms.World.ContainerRef
  alias AgenticRealms.World.Queries
  alias AgenticRealms.World.Schemas.Room

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

  @doc """
  Feature 018 — remove an entity from the world. First-class, event-sourced
  removal: dispatches `RemoveEntity` to the `Entity` aggregate, which emits
  `EntityRemoved` (the read-model row is then deleted by the projector, the
  witness announces an NPC's departure, and the NPC-mind process manager
  terminates the mind). Returns `:ok`, or `{:error, :not_found}` for an unknown
  or already-removed entity (idempotent).
  """
  @spec remove_entity(String.t()) :: :ok | {:error, atom()}
  def remove_entity(entity_id) when is_binary(entity_id) do
    WorldApp.dispatch(%RemoveEntity{entity_id: entity_id}, consistency: :strong)
  end

  @doc "Remove an NPC clone (thin alias over `remove_entity/1`)."
  @spec remove_npc(String.t()) :: :ok | {:error, atom()}
  def remove_npc(npc_id) when is_binary(npc_id), do: remove_entity(npc_id)

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
end
