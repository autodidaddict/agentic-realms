defmodule AgenticRealmsWeb.LandingLive do
  use AgenticRealmsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player}>
      <div class="ar-landing">
        <div class="ar-landing-hero">
          <img
            src={~p"/images/logo-wordmark.png"}
            alt="Agentic Realms"
            class="ar-landing-logo ar-landing-logo-plate"
          />
          <img
            src={~p"/images/logo-wordmark-flat.png"}
            alt="Agentic Realms"
            class="ar-landing-logo ar-landing-logo-flat"
          />
        </div>
        <p class="ar-landing-desc">
          Enter a living world shaped by AI-driven agents. Explore dark taverns, craft spells,
          negotiate with NPCs who remember your choices, and forge your own story in a realm where
          every action has consequences. Whether you play as an adventurer or build worlds as a wizard,
          Agentic Realms brings the depth of tabletop role-playing to the browser.
        </p>
        <%= if is_nil(@current_player) do %>
          <div class="ar-landing-actions">
            <.link navigate={~p"/login"} class="ar-nav-link">Log In</.link>
            <.link navigate={~p"/register"} class="ar-nav-link ar-nav-link-primary">
              Create Account
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
