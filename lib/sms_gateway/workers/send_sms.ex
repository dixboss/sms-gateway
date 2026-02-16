defmodule SmsGateway.Workers.SendSms do
  @moduledoc """
  Oban worker that sends SMS messages via the Huawei E303 modem.

  Job queue: :sms_send (limit: 6 concurrent)
  Retry policy: 3 attempts with exponential backoff

  Workflow:
  1. Mark message as :sending
  2. Call Modem.Client.send_sms/2
  3. On success: mark as :sent with modem_message_id
  4. On error: retry or mark as :failed

  Retryable errors:
  - Modem unreachable (timeout)
  - Circuit breaker open
  - Modem busy (code 113)
  - Network error (code 115)
  - Temporary network unavailable (code 118)

  Non-retryable errors:
  - Invalid phone number (code 117)
  - SMS too long (validation)
  - Modem SMS box full (code 114) - requires admin intervention
  """

  use Oban.Worker,
    queue: :sms_send,
    max_attempts: 3

  require Logger

  alias SmsGateway.Sms.Message

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}}) do
    Logger.info("SendSms worker processing message: #{message_id}")

    with {:ok, message} <- load_message(message_id),
         :ok <- mark_sending(message),
         {:ok, modem_message_id} <- send_via_modem(message),
         :ok <- mark_sent(message, modem_message_id) do
      Logger.info("SMS sent successfully: #{message_id}")
      :ok
    else
      {:error, :not_found} ->
        Logger.error("Message not found: #{message_id}")
        {:cancel, "Message not found"}

      {:error, :circuit_breaker_open} ->
        Logger.warning("Circuit breaker open, will retry")
        {:snooze, 60}

      {:error, {:retryable, reason}} ->
        Logger.warning("Retryable error: #{inspect(reason)}")
        {:error, reason}

      {:error, {:non_retryable, reason}} ->
        Logger.error("Non-retryable error: #{inspect(reason)}")
        mark_failed(message_id, reason)
        {:cancel, reason}

      {:error, reason} ->
        Logger.error("Unknown error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # Message Operations
  # ============================================================================

  defp load_message(message_id) do
    case Ash.get(Message, message_id) do
      {:ok, message} -> {:ok, message}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp mark_sending(message) do
    case Ash.update(message, %{status: :sending}) do
      {:ok, _updated} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to mark message as sending: #{inspect(reason)}")
        {:error, {:non_retryable, "Failed to update status"}}
    end
  end

  defp mark_sent(message, modem_message_id) do
    case Ash.update(
           message,
           %{
             modem_message_id: modem_message_id
           },
           action: :mark_sent
         ) do
      {:ok, _updated} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to mark message as sent: #{inspect(reason)}")
        {:error, {:retryable, "Failed to update status"}}
    end
  end

  defp mark_failed(message_id, reason) do
    case Ash.get(Message, message_id) do
      {:ok, message} ->
        error_message = format_error_message(reason)

        case Ash.update(message, %{error_message: error_message}, action: :mark_failed) do
          {:ok, _} ->
            Logger.info("Marked message as failed: #{message_id}")

          {:error, err} ->
            Logger.error("Failed to mark message as failed: #{inspect(err)}")
        end

      {:error, _} ->
        Logger.error("Message not found for marking failed: #{message_id}")
    end
  end

  # ============================================================================
  # Modem Communication
  # ============================================================================

  defp send_via_modem(message) do
    case SmsGateway.Modem.Client.send_sms(message.phone_number, message.content) do
      {:ok, modem_message_id} ->
        {:ok, modem_message_id}

      {:error, :circuit_breaker_open} ->
        {:error, :circuit_breaker_open}

      {:error, {:http_error, status_code}} ->
        classify_http_error(status_code)

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        {:error, {:retryable, :timeout}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:retryable, reason}}

      {:error, reason} ->
        classify_modem_error(reason)
    end
  end

  # ============================================================================
  # Error Classification
  # ============================================================================

  defp classify_http_error(status_code) when status_code >= 500 do
    # Server errors are typically retryable
    {:error, {:retryable, "HTTP #{status_code}"}}
  end

  defp classify_http_error(status_code) do
    # Client errors are typically non-retryable
    {:error, {:non_retryable, "HTTP #{status_code}"}}
  end

  defp classify_modem_error(reason) when is_binary(reason) do
    cond do
      # Huawei modem error codes
      String.contains?(reason, "113") ->
        # Modem busy
        {:error, {:retryable, "Modem busy (113)"}}

      String.contains?(reason, "114") ->
        # SMS box full - requires intervention
        {:error, {:non_retryable, "Modem SMS box full (114)"}}

      String.contains?(reason, "115") ->
        # Network error
        {:error, {:retryable, "Network error (115)"}}

      String.contains?(reason, "117") ->
        # Invalid phone number
        {:error, {:non_retryable, "Invalid phone number (117)"}}

      String.contains?(reason, "118") ->
        # Network temporarily unavailable
        {:error, {:retryable, "Network unavailable (118)"}}

      true ->
        # Unknown error - retry to be safe
        {:error, {:retryable, reason}}
    end
  end

  defp classify_modem_error(reason) do
    {:error, {:retryable, inspect(reason)}}
  end

  defp format_error_message(reason) when is_binary(reason), do: reason
  defp format_error_message(reason), do: inspect(reason)
end
