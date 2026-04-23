defmodule AgenticRealmsWeb.PlayerSessionController do
  use AgenticRealmsWeb, :controller

  alias AgenticRealms.Accounts
  alias AgenticRealmsWeb.PlayerAuth

  def create(conn, %{"player" => %{"username" => username, "password" => password}}) do
    if player = Accounts.get_player_by_username_and_password(username, password) do
      PlayerAuth.log_in_player(conn, player)
    else
      conn
      |> put_flash(:error, "Invalid username or password")
      |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    PlayerAuth.log_out_player(conn)
  end
end
