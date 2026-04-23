defmodule AgenticRealmsWeb.PlayerRegistrationLive do
  use AgenticRealmsWeb, :live_view

  alias AgenticRealms.Accounts
  alias AgenticRealms.Accounts.Player

  @impl true
  def mount(_params, _session, socket) do
    changeset = Accounts.change_player_registration(%Player{})

    {:ok,
     socket
     |> assign(:page_title, "Create Account")
     |> assign(:check_errors, false)
     |> assign_form(changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="ar-auth-page">
        <div class="ar-auth-card">
          <h1 class="ar-auth-title">Create Account</h1>
          <.form
            for={@form}
            id="registration-form"
            phx-submit="save"
            phx-change="validate"
            phx-trigger-action={@trigger_submit}
            action={~p"/login"}
            method="post"
          >
            <div class="ar-auth-field">
              <.input
                field={@form[:username]}
                type="text"
                label="Username"
                class="ar-auth-input"
                required
                phx-debounce="blur"
              />
            </div>
            <div class="ar-auth-field">
              <.input
                field={@form[:password]}
                type="password"
                label="Password"
                class="ar-auth-input"
                required
                phx-debounce="blur"
              />
            </div>
            <div class="ar-auth-field">
              <.input
                field={@form[:password_confirmation]}
                type="password"
                label="Confirm Password"
                class="ar-auth-input"
                required
                phx-debounce="blur"
              />
            </div>
            <button type="submit" class="ar-auth-submit" phx-disable-with="Creating account...">
              Create Account
            </button>
          </.form>
          <p class="ar-auth-footer">
            Already have an account? <.link navigate={~p"/login"}>Log in</.link>
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save", %{"player" => player_params}, socket) do
    case Accounts.register_player(player_params) do
      {:ok, _player} ->
        {:noreply,
         socket
         |> assign(:trigger_submit, true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:check_errors, true)
         |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"player" => player_params}, socket) do
    changeset =
      %Player{}
      |> Accounts.change_player_registration(player_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "player")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false, trigger_submit: false)
    else
      assign(socket, form: form, trigger_submit: false)
    end
  end
end
