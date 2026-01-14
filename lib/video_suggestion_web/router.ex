defmodule VideoSuggestionWeb.Router do
  use VideoSuggestionWeb, :router

  import VideoSuggestionWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VideoSuggestionWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", VideoSuggestionWeb do
    pipe_through :browser
  end

  scope "/admin", VideoSuggestionWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_admin_user,
      on_mount: [
        {VideoSuggestionWeb.UserAuth, :require_authenticated},
        {VideoSuggestionWeb.UserAuth, :require_admin}
      ] do
      live "/videos/new", Admin.VideoUploadLive, :new
      live "/recommendations", Admin.RecommendationsLive, :index
      live "/similarity", Admin.VideoSimilarityLive, :index
      live "/similarity/:id", Admin.VideoSimilarityLive, :show
      live "/tags", Admin.TagExplorerLive, :index
      live "/tags/:id", Admin.TagExplorerLive, :show
      live "/search", Admin.VideoSearchLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", VideoSuggestionWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:video_suggestion, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: VideoSuggestionWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", VideoSuggestionWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{VideoSuggestionWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", VideoSuggestionWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{VideoSuggestionWeb.UserAuth, :mount_current_scope}] do
      live "/", FeedLive, :index
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
