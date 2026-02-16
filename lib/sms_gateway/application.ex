defmodule SmsGateway.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SmsGatewayWeb.Telemetry,
      SmsGateway.Repo,
      {DNSCluster, query: Application.get_env(:sms_gateway, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SmsGateway.PubSub},
      # Oban job queue processor
      {Oban, Application.fetch_env!(:sms_gateway, Oban)},
      # Start a worker by calling: SmsGateway.Worker.start_link(arg)
      # {SmsGateway.Worker, arg},
      # Start to serve requests, typically the last entry
      SmsGatewayWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SmsGateway.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SmsGatewayWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
