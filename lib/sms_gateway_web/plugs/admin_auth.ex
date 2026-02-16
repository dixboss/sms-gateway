defmodule SmsGatewayWeb.Plugs.AdminAuth do
  @moduledoc """
  Basic authentication plug for admin interface.

  Protects admin routes with HTTP Basic Auth.
  Credentials are configured in runtime.exs via environment variables:
  - ADMIN_USERNAME (default: admin)
  - ADMIN_PASSWORD (required in production, default: admin in dev)
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    with {username, password} <- Plug.BasicAuth.parse_basic_auth(conn),
         true <- valid_credentials?(username, password) do
      conn
    else
      _ -> unauthorized(conn)
    end
  end

  defp valid_credentials?(username, password) do
    expected_username = admin_username()
    expected_password = admin_password()

    Plug.Crypto.secure_compare(username, expected_username) and
      Plug.Crypto.secure_compare(password, expected_password)
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=\"SMS Gateway Admin\"")
    |> put_status(401)
    |> json(%{error: "Unauthorized"})
    |> halt()
  end

  defp admin_username do
    Application.get_env(:sms_gateway, :admin_username, "admin")
  end

  defp admin_password do
    Application.get_env(:sms_gateway, :admin_password, default_password())
  end

  defp default_password do
    if Mix.env() == :prod do
      raise """
      ADMIN_PASSWORD environment variable must be set in production!
      Set it in config/runtime.exs or via environment variable.
      """
    else
      "admin"
    end
  end
end
