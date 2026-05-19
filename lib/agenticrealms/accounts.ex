defmodule AgenticRealms.Accounts do
  alias AgenticRealms.Repo
  alias AgenticRealms.Accounts.Player

  def register_player(attrs) do
    %Player{}
    |> Player.registration_changeset(attrs)
    |> Repo.insert()
  end

  def get_player!(id), do: Repo.get!(Player, id)

  def get_player(id), do: Repo.get(Player, id)

  def get_player_by_username(username) when is_binary(username) do
    Repo.get_by(Player, username: username)
  end

  def get_player_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    player = get_player_by_username(username)

    if Player.valid_password?(player, password) do
      player
    end
  end

  def change_player_registration(%Player{} = player, attrs \\ %{}) do
    Player.registration_changeset(player, attrs)
  end

  def change_player_username(%Player{} = player, attrs \\ %{}) do
    Player.username_changeset(player, attrs)
  end

  def update_player_username(%Player{} = player, attrs) do
    player
    |> Player.username_changeset(attrs)
    |> Repo.update()
  end

  def change_player_password(%Player{} = player, attrs \\ %{}) do
    Player.password_changeset(player, attrs)
  end

  def update_player_password(%Player{} = player, current_password, attrs) do
    changeset = Player.password_changeset(player, attrs)

    if Player.valid_password?(player, current_password) do
      Repo.update(changeset)
    else
      {:error,
       changeset
       |> Ecto.Changeset.add_error(:current_password, "is not valid")
       |> Map.put(:action, :validate)}
    end
  end

  def update_player_preferences(%Player{} = player, attrs) do
    player
    |> Player.preferences_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a player's account.

  Per FR-023, any objects the player is carrying are returned to the room
  they were in at the time of deletion. If the player has no current room
  (never played, or their last room is gone), carried objects fall back to
  the seeded starting room so they remain reachable.

  Each return is dispatched as a real `DropObject` Commanded command so
  the destination room's aggregate stays in sync with the read model —
  patching `world_objects` directly here would leave the aggregate
  unaware that the object is now in its room, breaking subsequent takes.
  """
  def delete_player(%Player{} = player) do
    alias AgenticRealms.World.{Queries, Seed}

    target_room_id =
      case Queries.current_room_of(player.id) do
        {:ok, room_id} -> room_id
        _ -> Seed.starting_room_id()
      end

    # Short-circuit on any DropObject failure. If we just `Enum.each`'d
    # and ignored errors, a partial cleanup would leave objects in a
    # half-state (some dropped to the room, others still carrying the
    # deleted player_id) AND the `Repo.delete(player)` call would then
    # fail on the `world_objects.player_id` FK constraint, leaving the
    # account half-deleted and the world half-cleaned.
    with :ok <- drop_carried_objects(player.id, target_room_id),
         {:ok, deleted} <- Repo.delete(player) do
      {:ok, deleted}
    end
  end

  defp drop_carried_objects(player_id, target_room_id) do
    alias AgenticRealms.World.Application, as: WorldApp
    alias AgenticRealms.World.Commands.DropObject
    alias AgenticRealms.World.Queries

    Queries.list_inventory(player_id)
    |> Enum.reduce_while(:ok, fn item, _acc ->
      case WorldApp.dispatch(
             %DropObject{
               room_id: target_room_id,
               player_id: player_id,
               object_id: item.id
             },
             consistency: :strong
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:drop_object_failed, item.id, reason}}}
      end
    end)
  end
end
