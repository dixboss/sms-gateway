defmodule SmsGateway.Workers.UpdateStatus do
  @moduledoc """
  Oban worker that periodically updates delivery status of sent SMS messages.

  Job queue: :sms_status
  Schedule: Every 5 minutes (configured via Oban cron)

  Workflow:
  1. Query all messages with status :sent that are older than 5 minutes
  2. For each message, check delivery status via modem
  3. Update message status to :delivered or :failed

  This worker is scheduled via Oban cron configuration in config.exs:

      config :sms_gateway, Oban,
        queues: [sms_status: 3],
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"*/5 * * * *", SmsGateway.Workers.UpdateStatus}
           ]}
        ]
  """

  use Oban.Worker,
    queue: :sms_status,
    max_attempts: 1

  require Logger

  alias SmsGateway.Sms.Message

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("UpdateStatus worker checking message delivery statuses")

    messages = get_pending_messages()
    count = Enum.count(messages)

    Logger.info("Found #{count} messages to check")

    results =
      messages
      |> Enum.map(&update_message_status/1)
      |> Enum.frequencies()

    Logger.info(
      "Status update complete: #{results[:delivered] || 0} delivered, #{results[:failed] || 0} failed, #{results[:error] || 0} errors"
    )

    :ok
  end

  # ============================================================================
  # Query Pending Messages
  # ============================================================================

  defp get_pending_messages do
    # Get messages that are :sent but not yet :delivered or :failed
    # and were sent at least 5 minutes ago to allow time for delivery
    five_minutes_ago = DateTime.add(DateTime.utc_now(), -300, :second)

    case Ash.read(Message, action: :by_status, actor: nil) do
      {:ok, messages} ->
        messages
        |> Enum.filter(fn msg ->
          msg.status == :sent and
            msg.modem_message_id != nil and
            msg.sent_at != nil and
            DateTime.compare(msg.sent_at, five_minutes_ago) == :lt
        end)

      {:error, reason} ->
        Logger.error("Failed to query messages: #{inspect(reason)}")
        []
    end
  end

  # ============================================================================
  # Update Individual Message Status
  # ============================================================================

  defp update_message_status(message) do
    case check_delivery_status(message.modem_message_id) do
      {:ok, :delivered} ->
        mark_delivered(message)
        :delivered

      {:ok, :failed} ->
        mark_failed(message, "Delivery failed (modem reported)")
        :failed

      {:ok, :pending} ->
        # Still pending, check again next time
        Logger.debug("Message #{message.id} still pending delivery")
        :pending

      {:error, reason} ->
        Logger.warning("Failed to check status for message #{message.id}: #{inspect(reason)}")

        :error
    end
  end

  defp check_delivery_status(modem_message_id) do
    case SmsGateway.Modem.Client.get_status(modem_message_id) do
      {:ok, status} when status in [:delivered, :failed, :pending] ->
        {:ok, status}

      {:ok, status} ->
        Logger.warning("Unknown status from modem: #{inspect(status)}")
        {:ok, :pending}

      {:error, :circuit_breaker_open} ->
        # Circuit breaker open, skip this check cycle
        Logger.warning("Circuit breaker open, skipping status check")
        {:error, :circuit_breaker_open}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Status Updates
  # ============================================================================

  defp mark_delivered(message) do
    case Ash.update(message, %{}, action: :mark_delivered) do
      {:ok, _} ->
        Logger.info("Message #{message.id} marked as delivered")

      {:error, reason} ->
        Logger.error("Failed to mark message as delivered: #{inspect(reason)}")
    end
  end

  defp mark_failed(message, error_message) do
    case Ash.update(message, %{error_message: error_message}, action: :mark_failed) do
      {:ok, _} ->
        Logger.info("Message #{message.id} marked as failed")

      {:error, reason} ->
        Logger.error("Failed to mark message as failed: #{inspect(reason)}")
    end
  end
end
