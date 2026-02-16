defmodule SmsGateway.Repo do
  use Ecto.Repo,
    otp_app: :sms_gateway,
    adapter: Ecto.Adapters.Postgres

  def installed_extensions do
    # List of PostgreSQL extensions used by the application
    # Add extensions as needed (e.g., "uuid-ossp" for UUID generation)
    []
  end

  # Required by AshPostgres 2.6.32+ for atomic actions control
  def disable_atomic_actions?, do: false
end
