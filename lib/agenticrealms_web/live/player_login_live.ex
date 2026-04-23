defmodule AgenticRealmsWeb.PlayerLoginLive do
  use AgenticRealmsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    username = Phoenix.Flash.get(socket.assigns.flash, :username)
    form = to_form(%{"username" => username}, as: "player")

    {:ok,
     socket
     |> assign(:page_title, "Log In")
     |> assign(:form, form)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="ar-auth-page">
        <div class="ar-auth-card">
          <h1 class="ar-auth-title">Log In</h1>
          <.form for={@form} id="login-form" action={~p"/login"} phx-update="ignore">
            <div class="ar-auth-field">
              <.input
                field={@form[:username]}
                type="text"
                label="Username"
                class="ar-auth-input"
                required
              />
            </div>
            <div class="ar-auth-field">
              <.input
                field={@form[:password]}
                type="password"
                label="Password"
                class="ar-auth-input"
                required
              />
            </div>
            <button type="submit" class="ar-auth-submit" phx-disable-with="Logging in...">
              Log In
            </button>
          </.form>
          <p class="ar-auth-footer">
            Don't have an account? <.link navigate={~p"/register"}>Create one</.link>
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
