defmodule SmsGateway.Modem.StatusMonitor do
  @moduledoc """
  GenServer that periodically monitors modem health and connectivity.

  Performs health checks every N seconds (default: 60s) to:
  - Check signal strength and network connectivity
  - Monitor battery level (if applicable)
  - Detect modem disconnections
  - Publish telemetry metrics

  If modem becomes unreachable, temporarily pauses the Oban job queue
  to prevent job failures.
  """

  use GenServer

  require Logger

  # 60 seconds (configurable)
  @health_check_interval 60_000

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  rescue
    _ -> {:error, :unavailable}
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(opts) do
    Logger.info("Modem.StatusMonitor starting")

    check_interval = Keyword.get(opts, :health_check_interval, @health_check_interval)

    state = %{
      check_interval: check_interval,
      last_status: nil,
      is_healthy: true,
      check_timer: schedule_check(check_interval)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:check_health, state) do
    new_state =
      case SmsGateway.Modem.Client.health_check() do
        {:ok, health_info} ->
          handle_healthy_check(health_info, state)

        {:error, reason} ->
          handle_unhealthy_check(reason, state)
      end

    {:noreply, %{new_state | check_timer: schedule_check(new_state.check_interval)}}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    {:reply, state.last_status, state}
  end

  # ============================================================================
  # Health Check Logic
  # ============================================================================

  defp handle_healthy_check(health_info, state) do
    signal_strength = health_info.signal_strength || 0

    Logger.debug("Modem health: signal=#{signal_strength}% network=#{health_info.network_name}")

    # Publish metrics
    :telemetry.execute(
      [:sms_gateway, :modem, :signal_strength],
      %{value: signal_strength},
      %{network: health_info.network_name}
    )

    # Warn if signal is low
    if signal_strength < 20 do
      Logger.warning("Low modem signal: #{signal_strength}%")
    end

    # If modem was unhealthy, resume Oban queue
    if not state.is_healthy do
      Logger.info("Modem is back online, resuming job queue")
      pause_queue(false)
    end

    %{state | last_status: health_info, is_healthy: true}
  end

  defp handle_unhealthy_check(reason, state) do
    Logger.error("Modem health check failed: #{inspect(reason)}")

    # If modem was healthy, pause Oban queue to prevent failures
    if state.is_healthy do
      Logger.warning("Modem unreachable, pausing job queue")
      pause_queue(true)
    end

    # Publish error metric
    :telemetry.execute(
      [:sms_gateway, :modem, :error],
      %{count: 1},
      %{reason: inspect(reason)}
    )

    %{state | is_healthy: false}
  end

  # ============================================================================
  # Oban Queue Management
  # ============================================================================

  defp pause_queue(should_pause) do
    if should_pause do
      Oban.pause_queue(queue: :sms_send)
      Logger.warning("Paused :sms_send queue")
    else
      Oban.resume_queue(queue: :sms_send)
      Logger.info("Resumed :sms_send queue")
    end
  rescue
    e ->
      Logger.error("Failed to pause/resume Oban queue: #{inspect(e)}")
  end

  # ============================================================================
  # Scheduling
  # ============================================================================

  defp schedule_check(interval) do
    Process.send_after(self(), :check_health, interval)
  end
end
