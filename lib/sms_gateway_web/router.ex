defmodule SmsGatewayWeb.Router do
  use SmsGatewayWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug SmsGatewayWeb.Plugs.ApiAuth
  end

  scope "/api", SmsGatewayWeb do
    pipe_through :api

    # Public health check endpoint
    get "/health", HealthController, :show
  end

  scope "/api/v1", SmsGatewayWeb.Api.V1 do
    pipe_through :api_authenticated

    # SMS Messages API
    resources "/messages", MessageController, only: [:create, :index, :show]
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:sms_gateway, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
