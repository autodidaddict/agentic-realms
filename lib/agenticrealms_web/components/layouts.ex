defmodule AgenticRealmsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AgenticRealmsWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  Shows an authenticated navigation bar when `current_player` is present,
  or unauthenticated links (Log In / Create Account) when it's nil.

  ## Examples

      <Layouts.app flash={@flash} current_player={@current_player}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_player, :map, default: nil, doc: "the current authenticated player"

  attr :game_mode, :atom,
    default: nil,
    doc: "current game mode (:player or :wizard) — only set on the game page"

  attr :is_wizard, :boolean,
    default: false,
    doc:
      "feature 014 FR-WIZ-3 — gates the Wizard/Player top-bar switch. Non-wizards never see the switch."

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="ar-navbar">
      <div class="ar-navbar-left">
        <%= if @current_player do %>
          <.link navigate={~p"/"} class="ar-nav-home" title="Home">
            <.icon name="hero-home-solid" class="ar-nav-icon" />
          </.link>
          <%= if is_nil(@game_mode) do %>
            <.link navigate={~p"/play"} class="ar-nav-link ar-nav-play">
              <img src={~p"/images/logo-mark.png"} alt="" class="ar-nav-play-icon" /> Play
            </.link>
          <% end %>
        <% else %>
          <span class="ar-nav-brand">
            <img src={~p"/images/logo-mark.png"} alt="" class="ar-nav-brand-mark" />
            <span>Agentic Realms</span>
          </span>
        <% end %>
      </div>
      <div class="ar-navbar-right">
        <%= if @current_player do %>
          <%= if @game_mode && @is_wizard do %>
            <div class="mode-switch" role="tablist">
              <button
                class={[@game_mode == :player && "active"]}
                phx-click="switch_mode"
                phx-value-mode="player"
              >
                <span class="dot" /> Player
              </button>
              <button
                class={[@game_mode == :wizard && "active"]}
                phx-click="switch_mode"
                phx-value-mode="wizard"
              >
                <span class="dot" /> Wizard
              </button>
            </div>
          <% end %>
          <div class="ar-nav-dropdown" id="user-menu">
            <button
              class="ar-nav-username"
              phx-click={
                JS.toggle(
                  to: "#user-menu-items",
                  in: {"transition-opacity duration-100", "opacity-0", "opacity-100"},
                  out: {"transition-opacity duration-75", "opacity-100", "opacity-0"}
                )
              }
            >
              {@current_player.username}
              <.icon name="hero-chevron-down-mini" class="ar-nav-chevron" />
            </button>
            <div id="user-menu-items" class="ar-nav-menu" style="display: none;">
              <.link navigate={~p"/settings"} class="ar-nav-menu-item">Settings</.link>
              <.link href={~p"/logout"} method="delete" class="ar-nav-menu-item ar-nav-menu-danger">
                Log Out
              </.link>
            </div>
          </div>
        <% else %>
          <.link navigate={~p"/login"} class="ar-nav-link">Log In</.link>
          <.link navigate={~p"/register"} class="ar-nav-link ar-nav-link-primary">
            Create Account
          </.link>
        <% end %>
      </div>
    </header>

    <main class="ar-main">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the game layout — a minimal full-viewport shell with no navbar.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  slot :inner_block, required: true

  def game(assigns) do
    ~H"""
    {render_slot(@inner_block)}
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
