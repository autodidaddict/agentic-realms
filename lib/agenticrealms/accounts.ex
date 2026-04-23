defmodule AgenticRealms.Accounts do
  alias AgenticRealms.Repo
  alias AgenticRealms.Accounts.Player

  def register_player(attrs) do
    %Player{}
    |> Player.registration_changeset(attrs)
    |> Repo.insert()
  end

  def get_player!(id), do: Repo.get!(Player, id)

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

  def delete_player(%Player{} = player) do
    Repo.delete(player)
  end
end
