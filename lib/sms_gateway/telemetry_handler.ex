defmodule SmsGateway.TelemetryHandler do
  @moduledoc """
  Telemetry event handler for SMS Gateway metrics.

  Attaches handlers to telemetry events and logs important metrics.
  """

  require Logger

  @doc """
  Attach telemetry handlers during application startup.
  """
  def attach_handlers do
    events = [
      [:sms_gateway, :sms, :sent],
      [:sms_gateway, :sms, :failed],
      [:sms_gateway, :sms, :delivered],
      [:sms_gateway, :sms, :received],
      [:sms_gateway, :modem, :signal_strength],
      [:sms_gateway, :modem, :error],
      [:sms_gateway, :queue, :status]
    ]

    :telemetry.attach_many(
      "sms-gateway-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc """
  Handle telemetry events and log them with structured metadata.
  """
  def handle_event([:sms_gateway, :sms, :sent], measurements, metadata, _config) do
    Logger.info("SMS sent",
      phone: metadata.phone,
      count: measurements.count
    )
  end

  def handle_event([:sms_gateway, :sms, :failed], measurements, metadata, _config) do
    Logger.warning("SMS failed",
      phone: metadata.phone,
      reason: metadata.reason,
      count: measurements.count
    )
  end

  def handle_event([:sms_gateway, :sms, :delivered], measurements, metadata, _config) do
    Logger.info("SMS delivered",
      phone: metadata.phone,
      count: measurements.count
    )
  end

  def handle_event([:sms_gateway, :sms, :received], measurements, metadata, _config) do
    Logger.info("SMS received",
      phone: metadata.phone,
      count: measurements.count
    )
  end

  def handle_event([:sms_gateway, :modem, :signal_strength], measurements, metadata, _config) do
    signal = measurements.value

    if signal < 20 do
      Logger.warning("Low modem signal",
        signal_strength: signal,
        network: metadata.network
      )
    else
      Logger.debug("Modem signal",
        signal_strength: signal,
        network: metadata.network
      )
    end
  end

  def handle_event([:sms_gateway, :modem, :error], measurements, metadata, _config) do
    Logger.error("Modem error",
      count: measurements.count,
      reason: metadata.reason
    )
  end

  def handle_event([:sms_gateway, :queue, :status], measurements, metadata, _config) do
    Logger.debug("Queue status",
      queue: metadata.queue,
      pending: measurements.pending,
      executing: measurements.executing
    )
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
