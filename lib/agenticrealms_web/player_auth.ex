defmodule AgenticRealmsWeb.PlayerAuth do
  use AgenticRealmsWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias AgenticRealms.Accounts

  def fetch_current_player(conn, _opts) do
    player_id = get_session(conn, :player_id)
    player = player_id && Accounts.get_player!(player_id)
    assign(conn, :current_player, player)
  rescue
    Ecto.NoResultsError ->
      conn
      |> delete_session(:player_id)
      |> assign(:current_player, nil)
  end

  def require_authenticated_player(conn, _opts) do
    if conn.assigns[:current_player] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  def redirect_if_player_is_authenticated(conn, _opts) do
    if conn.assigns[:current_player] do
      conn
      |> redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

  def log_in_player(conn, player) do
    conn
    |> renew_session()
    |> put_session(:player_id, player.id)
    |> redirect(to: ~p"/")
  end

  def log_out_player(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/")
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_player(socket, session)

    if socket.assigns.current_player do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_player(socket, session)

    if socket.assigns.current_player do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:mount_current_player, _params, session, socket) do
    {:cont, mount_current_player(socket, session)}
  end

  defp mount_current_player(socket, session) do
    Phoenix.Component.assign_new(socket, :current_player, fn ->
      if player_id = session["player_id"] do
        try do
          Accounts.get_player!(player_id)
        rescue
          Ecto.NoResultsError -> nil
        end
      end
    end)
  end
end
