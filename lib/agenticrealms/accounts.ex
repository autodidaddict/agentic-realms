defmodule AgenticRealms.Accounts do
  alias AgenticRealms.Repo
  alias AgenticRealms.Accounts.Player

  @spec register_player(map()) :: {:ok, Player.t()} | {:error, Ecto.Changeset.t()}
  def register_player(attrs) do
    %Player{}
    |> Player.registration_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_player!(term()) :: Player.t()
  def get_player!(id), do: Repo.get!(Player, id)

  @spec get_player(term()) :: Player.t() | nil
  def get_player(id), do: Repo.get(Player, id)

  @spec get_player_by_username(String.t()) :: Player.t() | nil
  def get_player_by_username(username) when is_binary(username) do
    Repo.get_by(Player, username: username)
  end

  @spec get_player_by_username_and_password(String.t(), String.t()) :: Player.t() | nil
  def get_player_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    player = get_player_by_username(username)

    if Player.valid_password?(player, password) do
      player
    end
  end

  @spec change_player_registration(Player.t(), map()) :: Ecto.Changeset.t()
  def change_player_registration(%Player{} = player, attrs \\ %{}) do
    Player.registration_changeset(player, attrs)
  end

  @spec change_player_username(Player.t(), map()) :: Ecto.Changeset.t()
  def change_player_username(%Player{} = player, attrs \\ %{}) do
    Player.username_changeset(player, attrs)
  end

  @spec update_player_username(Player.t(), map()) ::
          {:ok, Player.t()} | {:error, Ecto.Changeset.t()}
  def update_player_username(%Player{} = player, attrs) do
    player
    |> Player.username_changeset(attrs)
    |> Repo.update()
  end

  @spec change_player_password(Player.t(), map()) :: Ecto.Changeset.t()
  def change_player_password(%Player{} = player, attrs \\ %{}) do
    Player.password_changeset(player, attrs)
  end

  @spec update_player_password(Player.t(), String.t(), map()) ::
          {:ok, Player.t()} | {:error, Ecto.Changeset.t()}
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

  @spec update_player_preferences(Player.t(), map()) ::
          {:ok, Player.t()} | {:error, Ecto.Changeset.t()}
  def update_player_preferences(%Player{} = player, attrs) do
    player
    |> Player.preferences_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Promote a player to wizard status. Idempotent on already-wizard accounts.

  Intended invocation: `iex` during local development. No UI for promotion
  ships in feature 014 milestone 1 — see
  `specs/014-item-blueprints/spec.md` Clarifications + FR-WIZ-2.
  """
  @spec promote_to_wizard(integer()) ::
          {:ok, %Player{}} | {:error, :not_found}
  def promote_to_wizard(player_id) when is_integer(player_id) do
    case Repo.get(Player, player_id) do
      nil ->
        {:error, :not_found}

      %Player{is_wizard: true} = player ->
        {:ok, player}

      %Player{} = player ->
        player
        |> Ecto.Changeset.change(is_wizard: true)
        |> Repo.update()
    end
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
  @spec delete_player(Player.t()) ::
          {:ok, Player.t()} | {:error, term()}
  def delete_player(%Player{} = player) do
    alias AgenticRealms.World.{Queries, Seed}

    target_room_id =
      case Queries.current_room_of(player.id) do
        {:ok, room_id} -> room_id
        _ -> Seed.starting_room_id()
      end

    with :ok <- drop_carried_objects(player.id, target_room_id),
         {:ok, deleted} <- Repo.delete(player) do
      {:ok, deleted}
    end
  end

  defp drop_carried_objects(player_id, target_room_id) do
    alias AgenticRealms.World.Commands, as: WorldCommands
    alias AgenticRealms.World.ContainerRef
    alias AgenticRealms.World.Queries

    Queries.list_inventory(player_id)
    |> Enum.reduce_while(:ok, fn item, _acc ->
      case WorldCommands.move_entity(
             item.id,
             ContainerRef.player(player_id),
             ContainerRef.room(target_room_id),
             :dropped
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:drop_object_failed, item.id, reason}}}
      end
    end)
  end
end
