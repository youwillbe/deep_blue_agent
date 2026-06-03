defmodule DeepBlueWeb.Router do
  use DeepBlueWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DeepBlueWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :stream do
    plug :accepts, ["json"]
  end

  # Durable Streams (streamkeeper)
  scope "/v1" do
    pipe_through :stream
    forward "/stream", DurableStreams.Protocol.Plug
  end

  # Chat routes
  scope "/", DeepBlueWeb do
    pipe_through :browser

    live_session :default do
      live "/", ChatLive.Index
      live "/sessions/:id", ChatLive.Show
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:deep_blue, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DeepBlueWeb.Telemetry
    end
  end
end
