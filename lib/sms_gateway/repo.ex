defmodule SmsGateway.Repo do
  use Ecto.Repo,
    otp_app: :sms_gateway,
    adapter: Ecto.Adapters.Postgres
end
