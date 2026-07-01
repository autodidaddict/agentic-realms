defmodule AgenticRealmsWeb.Router do
  use AgenticRealmsWeb, :router

  import AgenticRealmsWeb.PlayerAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AgenticRealmsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_player
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Feature 018 — External NPC Brains. The contract routes accept JSON and are
  # guarded by the shared-secret bearer token (fail-closed when unset).
  pipeline :npc_service do
    plug :accepts, ["json"]
    plug AgenticRealmsWeb.Plugs.RequireServiceToken
  end

  # Public routes (redirect if already authenticated)
  scope "/", AgenticRealmsWeb do
    pipe_through [:browser, :redirect_if_player_is_authenticated]

    live_session :redirect_if_authenticated,
      on_mount: [{AgenticRealmsWeb.PlayerAuth, :redirect_if_authenticated}] do
      live "/login", PlayerLoginLive
      live "/register", PlayerRegistrationLive
    end

    post "/login", PlayerSessionController, :create
  end

  # Public routes (no redirect)
  scope "/", AgenticRealmsWeb do
    pipe_through :browser

    live_session :public,
      on_mount: [{AgenticRealmsWeb.PlayerAuth, :mount_current_player}] do
      live "/", LandingLive
    end
  end

  # Authenticated routes
  scope "/", AgenticRealmsWeb do
    pipe_through [:browser, :require_authenticated_player]

    live_session :authenticated,
      on_mount: [{AgenticRealmsWeb.PlayerAuth, :ensure_authenticated}] do
      live "/play", GameLive
      live "/settings", PlayerSettingsLive
    end

    delete "/logout", PlayerSessionController, :delete
  end

  # Feature 018 — External NPC Brains. Authenticated service contract consumed by
  # the external mind worker: read identity, read surroundings, submit a move.
  scope "/api", AgenticRealmsWeb do
    pipe_through :npc_service

    get "/npc/:id/identity", NpcServiceController, :identity
    get "/npc/:id/surroundings", NpcServiceController, :surroundings
    post "/npc/:id/move", NpcServiceController, :move
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:agenticrealms, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AgenticRealmsWeb.Telemetry
    end
  end
end
