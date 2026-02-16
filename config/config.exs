# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sms_gateway,
  ecto_repos: [SmsGateway.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :sms_gateway, SmsGatewayWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SmsGatewayWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SmsGateway.PubSub,
  live_view: [signing_salt: "iIlUVtUE"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sms_gateway, SmsGateway.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Oban job processing
config :sms_gateway, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    # SMS sending queue: max 6 concurrent jobs (modem hardware limit: 6 SMS/minute)
    sms_send: [limit: 6],
    # Status update queue: max 3 concurrent jobs
    sms_status: [limit: 3]
  ],
  repo: SmsGateway.Repo

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
