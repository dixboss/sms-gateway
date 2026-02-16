defmodule SmsGateway.Modem.Client do
  @moduledoc """
  HTTP client for Huawei E303 modem with circuit breaker pattern.

  Provides functions to:
  - Send SMS via modem API
  - List incoming SMS messages
  - Check message delivery status
  - Monitor modem health

  Circuit breaker protects against repeated calls to a failing modem:
  - :closed (normal operation)
  - :open (5 consecutive failures -> back off for 5 minutes)
  - :half_open (testing if modem is back online)
  """

  require Logger
  import SweetXml

  @circuit_breaker_key :modem_circuit_breaker
  @max_failures 5
  # 5 minutes in ms
  @backoff_duration 300_000
  # 10 seconds
  @timeout 10_000

  defmodule CircuitBreaker do
    @moduledoc false
    defstruct state: :closed, failures: 0, opened_at: nil
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Send an SMS via the modem.

  Returns `{:ok, message_id}` on success or `{:error, reason}` on failure.
  """
  def send_sms(phone_number, content) do
    if circuit_breaker_open?() do
      {:error, :circuit_breaker_open}
    else
      call_modem(:send_sms, fn ->
        send_sms_impl(phone_number, content)
      end)
    end
  end

  @doc """
  List SMS messages from the modem inbox.

  Returns `{:ok, messages}` where messages is a list of message structs or
  `{:error, reason}` on failure.
  """
  def list_sms(box_type \\ 1) do
    if circuit_breaker_open?() do
      {:error, :circuit_breaker_open}
    else
      call_modem(:list_sms, fn ->
        list_sms_impl(box_type)
      end)
    end
  end

  @doc """
  Get delivery status of a sent SMS.

  Returns `{:ok, status}` where status is one of:
  - :pending
  - :sent
  - :delivered
  - :failed
  Or `{:error, reason}` on failure.
  """
  def get_status(modem_message_id) do
    if circuit_breaker_open?() do
      {:error, :circuit_breaker_open}
    else
      call_modem(:get_status, fn ->
        get_status_impl(modem_message_id)
      end)
    end
  end

  @doc """
  Check modem health and connectivity.

  Returns `{:ok, health_info}` with signal strength, network info, etc.
  or `{:error, reason}` on failure.
  """
  def health_check do
    if circuit_breaker_open?() do
      {:error, :circuit_breaker_open}
    else
      call_modem(:health_check, fn ->
        health_check_impl()
      end)
    end
  end

  @doc """
  Reset circuit breaker (for testing or manual recovery).
  """
  def reset_circuit_breaker do
    :persistent_term.erase(@circuit_breaker_key)
    Logger.info("Circuit breaker reset")
  end

  # ============================================================================
  # Implementation Functions
  # ============================================================================

  defp send_sms_impl(phone_number, content) do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    url = "#{base_url}/api/sms/send-sms"

    body =
      URI.encode_query(%{
        "phones[Phone]" => phone_number,
        "content" => content,
        "encode_type" => "gsm7_default"
      })

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    with {:ok, response} <- HTTPoison.post(url, body, headers, timeout: @timeout),
         {:ok, message_id} <- parse_send_sms_response(response.body) do
      {:ok, message_id}
    else
      error -> handle_modem_error(error)
    end
  end

  defp list_sms_impl(box_type) do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    url = "#{base_url}/api/sms/sms-list?page=1&count=20&box_type=#{box_type}"

    with {:ok, response} <- HTTPoison.get(url, [], timeout: @timeout),
         {:ok, messages} <- parse_list_sms_response(response.body) do
      {:ok, messages}
    else
      error -> handle_modem_error(error)
    end
  end

  defp get_status_impl(modem_message_id) do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    url = "#{base_url}/api/sms/send-status?message_id=#{modem_message_id}"

    with {:ok, response} <- HTTPoison.get(url, [], timeout: @timeout),
         {:ok, status} <- parse_get_status_response(response.body) do
      {:ok, status}
    else
      error -> handle_modem_error(error)
    end
  end

  defp health_check_impl do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    url = "#{base_url}/api/monitoring/status"

    with {:ok, response} <- HTTPoison.get(url, [], timeout: @timeout),
         {:ok, health_info} <- parse_health_check_response(response.body) do
      {:ok, health_info}
    else
      error -> handle_modem_error(error)
    end
  end

  # ============================================================================
  # XML Parsing
  # ============================================================================

  defp parse_send_sms_response(body) do
    case SweetXml.parse(body) do
      {:ok, xml} ->
        case SweetXml.xpath(xml, ~x"//message_id/text()"s) do
          nil -> {:error, :invalid_response}
          message_id -> {:ok, message_id}
        end

      {:error, _} ->
        {:error, :parse_error}
    end
  end

  defp parse_list_sms_response(body) do
    case SweetXml.parse(body) do
      {:ok, xml} ->
        messages =
          SweetXml.xpath(xml, ~x"//messages/message"l) |> Enum.map(&parse_sms_message/1)

        {:ok, messages}

      {:error, _} ->
        {:error, :parse_error}
    end
  end

  defp parse_sms_message(message_xml) do
    %{
      index: SweetXml.xpath(message_xml, ~x"//index/text()"s) |> String.to_integer(),
      phone: SweetXml.xpath(message_xml, ~x"//phone/text()"s),
      content: SweetXml.xpath(message_xml, ~x"//content/text()"s),
      date: SweetXml.xpath(message_xml, ~x"//date/text()"s),
      status: SweetXml.xpath(message_xml, ~x"//status/text()"s)
    }
  rescue
    # If parsing individual message fails, log and return minimal info
    e ->
      Logger.warning("Failed to parse SMS message: #{inspect(e)}")
      %{}
  end

  defp parse_get_status_response(body) do
    case SweetXml.parse(body) do
      {:ok, xml} ->
        status_str = SweetXml.xpath(xml, ~x"//status/text()"s)
        status_atom = parse_status_string(status_str)
        {:ok, status_atom}

      {:error, _} ->
        {:error, :parse_error}
    end
  end

  defp parse_health_check_response(body) do
    case SweetXml.parse(body) do
      {:ok, xml} ->
        health_info = %{
          signal_strength:
            SweetXml.xpath(xml, ~x"//signal_strength/text()"s) |> safe_to_integer(),
          network_type: SweetXml.xpath(xml, ~x"//network_type/text()"s),
          network_name: SweetXml.xpath(xml, ~x"//network_name/text()"s),
          battery_level: SweetXml.xpath(xml, ~x"//battery_level/text()"s) |> safe_to_integer(),
          connection_status: SweetXml.xpath(xml, ~x"//connection_status/text()"s)
        }

        {:ok, health_info}

      {:error, _} ->
        {:error, :parse_error}
    end
  end

  defp parse_status_string(status_str) when is_binary(status_str) do
    case String.downcase(status_str) do
      "delivered" -> :delivered
      "sent" -> :sent
      "pending" -> :pending
      "failed" -> :failed
      _ -> :unknown
    end
  end

  defp parse_status_string(_), do: :unknown

  defp safe_to_integer(nil), do: nil

  defp safe_to_integer(str) when is_binary(str) do
    String.to_integer(str)
  rescue
    ArgumentError -> nil
  end

  # ============================================================================
  # Circuit Breaker Logic
  # ============================================================================

  defp circuit_breaker_open?() do
    case :persistent_term.get(@circuit_breaker_key, nil) do
      %CircuitBreaker{state: :open, opened_at: opened_at} ->
        elapsed = System.monotonic_time(:millisecond) - opened_at

        if elapsed > @backoff_duration do
          # Transition to :half_open after backoff
          Logger.info("Circuit breaker entering half-open state after backoff")
          :persistent_term.put(@circuit_breaker_key, %CircuitBreaker{state: :half_open})
          false
        else
          true
        end

      _ ->
        false
    end
  end

  defp call_modem(operation, fun) do
    case fun.() do
      {:ok, result} ->
        record_success()
        {:ok, result}

      {:error, reason} ->
        record_failure(operation, reason)
        {:error, reason}
    end
  end

  defp record_success do
    new_breaker = %CircuitBreaker{
      state: :closed,
      failures: 0,
      opened_at: nil
    }

    :persistent_term.put(@circuit_breaker_key, new_breaker)
  end

  defp record_failure(operation, reason) do
    current = :persistent_term.get(@circuit_breaker_key, %CircuitBreaker{})
    new_failures = current.failures + 1

    Logger.warning("Modem operation #{operation} failed: #{inspect(reason)}")

    if new_failures >= @max_failures do
      Logger.error("Circuit breaker opening after #{@max_failures} failures")

      new_breaker = %CircuitBreaker{
        state: :open,
        failures: new_failures,
        opened_at: System.monotonic_time(:millisecond)
      }

      :persistent_term.put(@circuit_breaker_key, new_breaker)
    else
      new_breaker = %CircuitBreaker{
        state: :closed,
        failures: new_failures,
        opened_at: nil
      }

      :persistent_term.put(@circuit_breaker_key, new_breaker)
    end
  end

  defp handle_modem_error({:error, reason}), do: {:error, reason}

  defp handle_modem_error({:ok, response}) when is_map(response) do
    if response.status_code >= 400 do
      {:error, {:http_error, response.status_code}}
    else
      {:error, :unexpected_response}
    end
  end

  defp handle_modem_error(error), do: {:error, error}

  # ============================================================================
  # Configuration
  # ============================================================================

  defp config(key, default) do
    Application.get_env(:sms_gateway, :modem, []) |> Keyword.get(key, default) ||
      System.get_env(key_to_env_var(key), default)
  end

  defp key_to_env_var(key) do
    key |> Atom.to_string() |> String.upcase()
  end
end
