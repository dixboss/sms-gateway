defmodule SmsGatewayWeb.HealthController do
  @moduledoc """
  Health check endpoint for monitoring and load balancers.

  Endpoint:
  - GET /api/health (no authentication required)

  Returns overall system health including:
  - Application status
  - Database connectivity
  - Modem connectivity and signal strength
  - Oban queue status
  """

  use SmsGatewayWeb, :controller

  require Logger

  @doc """
  GET /api/health

  Health check endpoint (no authentication required).

  Response 200 (healthy):
  {
    "status": "healthy",
    "database": "connected",
    "modem": {
      "connected": true,
      "signal_strength": 85,
      "network": "Orange F"
    },
    "queue": {
      "pending": 5,
      "executing": 2
    }
  }

  Response 503 (degraded):
  {
    "status": "degraded",
    "database": "connected",
    "modem": {
      "connected": false,
      "error": "Connection timeout"
    },
    "queue": {
      "pending": 50,
      "executing": 0
    }
  }
  """
  def show(conn, _params) do
    health_status = %{
      status: "healthy",
      database: check_database(),
      modem: check_modem(),
      queue: check_queue()
    }

    # Determine overall status
    overall_status =
      if health_status.database == "connected" and
           health_status.modem[:connected] == true do
        "healthy"
      else
        "degraded"
      end

    health_status = %{health_status | status: overall_status}

    status_code = if overall_status == "healthy", do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(health_status)
  end

  # ============================================================================
  # Health Checks
  # ============================================================================

  defp check_database do
    case Ecto.Adapters.SQL.query(SmsGateway.Repo, "SELECT 1", []) do
      {:ok, _} -> "connected"
      {:error, _} -> "disconnected"
    end
  rescue
    _ -> "disconnected"
  end

  defp check_modem do
    case SmsGateway.Modem.StatusMonitor.get_status() do
      %{signal_strength: signal, network_name: network} when not is_nil(signal) ->
        %{
          connected: true,
          signal_strength: signal,
          network: network
        }

      {:error, :unavailable} ->
        %{
          connected: false,
          error: "Status monitor unavailable"
        }

      _ ->
        # Try direct health check
        case SmsGateway.Modem.Client.health_check() do
          {:ok, health_info} ->
            %{
              connected: true,
              signal_strength: health_info.signal_strength,
              network: health_info.network_name
            }

          {:error, :circuit_breaker_open} ->
            %{
              connected: false,
              error: "Circuit breaker open"
            }

          {:error, reason} ->
            %{
              connected: false,
              error: inspect(reason)
            }
        end
    end
  rescue
    e ->
      Logger.warning("Health check modem error: #{inspect(e)}")

      %{
        connected: false,
        error: "Exception: #{Exception.message(e)}"
      }
  end

  defp check_queue do
    try do
      # Get queue stats from Oban
      {:ok, stats} = Oban.check_queue(queue: :sms_send)

      %{
        pending: stats.available + stats.scheduled,
        executing: stats.executing
      }
    rescue
      _ ->
        %{
          pending: 0,
          executing: 0,
          error: "Unable to check queue"
        }
    end
  end
end
