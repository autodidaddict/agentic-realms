defmodule AgenticRealmsWeb.PlayerSettingsLive do
  use AgenticRealmsWeb, :live_view

  alias AgenticRealms.Accounts

  @impl true
  def mount(_params, _session, socket) do
    player = socket.assigns.current_player

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:username_form, to_form(Accounts.change_player_username(player), as: "player"))
     |> assign(:password_form, to_form(Accounts.change_player_password(player), as: "password"))
     |> assign(:username_saved, false)
     |> assign(:password_saved, false)
     |> assign(:show_delete_modal, false)
     |> assign(:delete_confirmation, "")
     |> assign(:trigger_submit, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player}>
      <div class="ar-settings-page">
        <h1 class="ar-settings-title">Settings</h1>

        <%!-- Username section --%>
        <div class="ar-settings-section">
          <h2 class="ar-settings-section-title">Username</h2>
          <.form
            for={@username_form}
            id="username-form"
            phx-submit="save_username"
            phx-change="validate_username"
          >
            <div class="ar-auth-field">
              <.input
                field={@username_form[:username]}
                type="text"
                label="Username"
                class="ar-auth-input"
                required
              />
            </div>
            <button type="submit" class="ar-settings-submit">Save Username</button>
            <p :if={@username_saved} class="ar-success-msg">Username updated successfully.</p>
          </.form>
        </div>

        <%!-- Password section --%>
        <div class="ar-settings-section">
          <h2 class="ar-settings-section-title">Change Password</h2>
          <.form
            for={@password_form}
            id="password-form"
            phx-submit="save_password"
            phx-change="validate_password"
          >
            <div class="ar-auth-field">
              <.input
                field={@password_form[:current_password]}
                type="password"
                label="Current Password"
                class="ar-auth-input"
                required
                name="current_password"
                value=""
              />
            </div>
            <div class="ar-auth-field">
              <.input
                field={@password_form[:password]}
                type="password"
                label="New Password"
                class="ar-auth-input"
                required
              />
            </div>
            <div class="ar-auth-field">
              <.input
                field={@password_form[:password_confirmation]}
                type="password"
                label="Confirm New Password"
                class="ar-auth-input"
                required
              />
            </div>
            <button type="submit" class="ar-settings-submit">Change Password</button>
            <p :if={@password_saved} class="ar-success-msg">Password updated successfully.</p>
          </.form>
        </div>

        <%!-- Theme & Density --%>
        <div class="ar-settings-section">
          <h2 class="ar-settings-section-title">Theme</h2>
          <div class="ar-auth-field">
            <label class="ar-auth-label">Color Theme</label>
            <div class="ar-pref-seg">
              <button
                :for={t <- ~w(phosphor paper dusk)}
                type="button"
                class={[
                  "ar-pref-btn",
                  if(@current_player.theme == t, do: "active")
                ]}
                phx-click={
                  JS.set_attribute({"data-theme", t}, to: "html")
                  |> JS.dispatch("phx:store-theme", detail: %{theme: t})
                  |> JS.push("set_preference", value: %{key: "theme", value: t})
                }
              >
                {t}
              </button>
            </div>
          </div>
          <div class="ar-auth-field">
            <label class="ar-auth-label">Density</label>
            <div class="ar-pref-seg">
              <button
                :for={d <- ~w(comfortable compact)}
                type="button"
                class={[
                  "ar-pref-btn",
                  if(@current_player.density == d, do: "active")
                ]}
                phx-click={
                  JS.set_attribute({"data-density", d}, to: "html")
                  |> JS.dispatch("phx:store-density", detail: %{density: d})
                  |> JS.push("set_preference", value: %{key: "density", value: d})
                }
              >
                {d}
              </button>
            </div>
          </div>
        </div>

        <%!-- Danger zone --%>
        <div class="ar-settings-section ar-danger-zone">
          <h2 class="ar-settings-section-title" style="color: var(--danger);">Danger Zone</h2>
          <p style="font-size: 13px; color: var(--ink-dim); margin-bottom: 12px;">
            Permanently delete your account and all associated data.
          </p>
          <button class="ar-danger-btn" phx-click="show_delete_modal">
            Delete Account
          </button>
        </div>

        <%!-- Delete confirmation modal --%>
        <%= if @show_delete_modal do %>
          <div class="ar-confirm-backdrop" phx-click="hide_delete_modal">
            <div class="ar-confirm-dialog" phx-click-away="hide_delete_modal">
              <h3 class="ar-confirm-title">Delete Account</h3>
              <p class="ar-confirm-text">
                This action is permanent and cannot be undone.
                All your data will be permanently removed.
              </p>
              <p class="ar-confirm-text">
                Type your username
                <strong style="color: var(--ink);">{@current_player.username}</strong>
                to confirm:
              </p>
              <div class="ar-auth-field">
                <input
                  type="text"
                  class="ar-auth-input"
                  id="delete-confirm-input"
                  phx-keyup="update_delete_confirmation"
                  value={@delete_confirmation}
                  autocomplete="off"
                />
              </div>
              <div class="ar-confirm-actions">
                <button class="ar-confirm-cancel" phx-click="hide_delete_modal">Cancel</button>
                <button
                  class="ar-danger-confirm-btn"
                  phx-click="confirm_delete"
                  disabled={@delete_confirmation != @current_player.username}
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate_username", %{"player" => params}, socket) do
    changeset =
      socket.assigns.current_player
      |> Accounts.change_player_username(params)
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket, username_form: to_form(changeset, as: "player"), username_saved: false)}
  end

  def handle_event("save_username", %{"player" => params}, socket) do
    case Accounts.update_player_username(socket.assigns.current_player, params) do
      {:ok, player} ->
        {:noreply,
         socket
         |> assign(:current_player, player)
         |> assign(:username_form, to_form(Accounts.change_player_username(player), as: "player"))
         |> assign(:username_saved, true)}

      {:error, changeset} ->
        {:noreply, assign(socket, username_form: to_form(changeset, as: "player"))}
    end
  end

  def handle_event("validate_password", %{"password" => params}, socket) do
    changeset =
      socket.assigns.current_player
      |> Accounts.change_player_password(params)
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket, password_form: to_form(changeset, as: "password"), password_saved: false)}
  end

  def handle_event(
        "save_password",
        %{"password" => params, "current_password" => current_password},
        socket
      ) do
    case Accounts.update_player_password(socket.assigns.current_player, current_password, params) do
      {:ok, player} ->
        {:noreply,
         socket
         |> assign(:current_player, player)
         |> assign(
           :password_form,
           to_form(Accounts.change_player_password(player), as: "password")
         )
         |> assign(:password_saved, true)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset, as: "password"))}
    end
  end

  def handle_event("set_preference", %{"key" => key, "value" => value}, socket) do
    case Accounts.update_player_preferences(socket.assigns.current_player, %{key => value}) do
      {:ok, player} ->
        {:noreply, assign(socket, :current_player, player)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("show_delete_modal", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: true, delete_confirmation: "")}
  end

  def handle_event("hide_delete_modal", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: false, delete_confirmation: "")}
  end

  def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation, value)}
  end

  def handle_event("confirm_delete", _params, socket) do
    player = socket.assigns.current_player

    if socket.assigns.delete_confirmation == player.username do
      {:ok, _} = Accounts.delete_player(player)

      {:noreply,
       socket
       |> redirect(to: ~p"/")}
    else
      {:noreply, socket}
    end
  end
end
