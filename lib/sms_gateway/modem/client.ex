defmodule SmsGateway.Modem.Client do
  @moduledoc """
  HTTP client for Huawei E303 modem with circuit breaker pattern and session token management.

  Provides functions to:
  - Send SMS via modem API (with XML request format)
  - List incoming SMS messages
  - Check message delivery status
  - Monitor modem health
  - Manage session tokens and cookies for authentication

  Circuit breaker protects against repeated calls to a failing modem:
  - :closed (normal operation)
  - :open (5 consecutive failures -> back off for 5 minutes)
  - :half_open (testing if modem is back online)

  Session Token Management:
  - Session info (SessionID + TokInfo) is fetched from /api/webserver/SesTokInfo
  - Both values are cached in ETS with TTL (5 minutes)
  - All requests include Cookie (SessionID) and __RequestVerificationToken (TokInfo) headers
  - Host header is included for broader modem compatibility (E3372, E3372h, E3131, E303)
  """

  require Logger
  import SweetXml

  @circuit_breaker_key :modem_circuit_breaker
  @token_cache_key :modem_session_token
  @max_failures 5
  # 5 minutes in ms
  @backoff_duration 300_000
  # 5 minutes in ms
  @token_ttl 300_000
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

  @doc """
  Clear cached session info (for testing or when session expires).
  """
  def clear_token_cache do
    ensure_token_cache_table()
    :ets.delete(@token_cache_key, :session)
    Logger.debug("Session info cache cleared")
  end

  # ============================================================================
  # Session Token Management
  # ============================================================================

  defp get_session_token do
    ensure_token_cache_table()

    case :ets.lookup(@token_cache_key, :session) do
      [{:session, {session_id, token}, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, {session_id, token}}
        else
          Logger.debug("Session expired, fetching new one")
          fetch_new_token()
        end

      [] ->
        fetch_new_token()
    end
  end

  defp fetch_new_token do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    url = "#{base_url}/api/webserver/SesTokInfo"

    # Extract host from base_url for Host header
    host = URI.parse(base_url).host || "192.168.8.1"
    headers = [{"Host", host}]

    case HTTPoison.get(url, headers, timeout: @timeout) do
      {:ok, %{status_code: 200, body: body}} ->
        case parse_session_response(body) do
          {:ok, {session_id, token}} ->
            cache_session(session_id, token)
            {:ok, {session_id, token}}

          {:error, reason} ->
            Logger.error("Failed to parse session info: #{inspect(reason)}")
            {:error, :session_parse_failed}
        end

      {:ok, %{status_code: status}} ->
        Logger.error("Session request failed with status: #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Session request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_session_response(body) do
    try do
      session_id = xpath(body, ~x"//response/SesInfo/text()"s)
      token = xpath(body, ~x"//response/TokInfo/text()"s)

      if session_id && session_id != "" && token && token != "" do
        {:ok, {session_id, token}}
      else
        Logger.error(
          "Missing session info - SesInfo: #{inspect(session_id)}, TokInfo: #{inspect(token)}"
        )

        {:error, :session_info_not_found}
      end
    rescue
      e ->
        Logger.error("XML parsing error: #{inspect(e)}")
        {:error, :xml_parse_error}
    end
  end

  defp cache_session(session_id, token) do
    ensure_token_cache_table()
    expires_at = System.monotonic_time(:millisecond) + @token_ttl
    :ets.insert(@token_cache_key, {:session, {session_id, token}, expires_at})

    Logger.debug(
      "Session info cached until #{expires_at} - SessionID: #{String.slice(session_id, 0..10)}..., Token: #{String.slice(token, 0..10)}..."
    )
  end

  defp ensure_token_cache_table do
    unless :ets.whereis(@token_cache_key) != :undefined do
      :ets.new(@token_cache_key, [:named_table, :public, :set])
    end
  end

  # ============================================================================
  # Implementation Functions
  # ============================================================================

  defp send_sms_impl(phone_number, content) do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    url = "#{base_url}/api/sms/send-sms"

    with {:ok, {session_id, token}} <- get_session_token(),
         {:ok, xml_body} <- build_sms_xml(phone_number, content),
         {:ok, response} <- send_authenticated_request(url, xml_body, session_id, token),
         {:ok, message_id} <- parse_send_sms_response(response.body) do
      {:ok, message_id}
    else
      error -> handle_modem_error(error)
    end
  end

  defp build_sms_xml(phone_number, content) do
    length = String.length(content)
    time = DateTime.utc_now() |> DateTime.to_string()

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <request>
      <Index>-1</Index>
      <Phones>
        <Phone>#{phone_number}</Phone>
      </Phones>
      <Sca></Sca>
      <Content>#{content}</Content>
      <Length>#{length}</Length>
      <Reserved>1</Reserved>
      <Date>#{time}</Date>
    </request>
    """

    {:ok, xml}
  end

  defp send_authenticated_request(url, body, session_id, token) do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    host = URI.parse(base_url).host || "192.168.8.1"

    headers = [
      {"Content-Type", "application/xml"},
      {"Cookie", session_id},
      {"__RequestVerificationToken", token},
      {"Host", host}
    ]

    HTTPoison.post(url, body, headers, timeout: @timeout)
  end

  defp list_sms_impl(box_type) do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    url = "#{base_url}/api/sms/sms-list?page=1&count=20&box_type=#{box_type}"

    with {:ok, {session_id, token}} <- get_session_token(),
         {:ok, response} <- send_authenticated_get(url, session_id, token),
         {:ok, messages} <- parse_list_sms_response(response.body) do
      {:ok, messages}
    else
      error -> handle_modem_error(error)
    end
  end

  defp send_authenticated_get(url, session_id, token) do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    host = URI.parse(base_url).host || "192.168.8.1"

    headers = [
      {"Cookie", session_id},
      {"__RequestVerificationToken", token},
      {"Host", host}
    ]

    HTTPoison.get(url, headers, timeout: @timeout)
  end

  defp get_status_impl(modem_message_id) do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    url = "#{base_url}/api/sms/send-status?message_id=#{modem_message_id}"

    with {:ok, {session_id, token}} <- get_session_token(),
         {:ok, response} <- send_authenticated_get(url, session_id, token),
         {:ok, status} <- parse_get_status_response(response.body) do
      {:ok, status}
    else
      error -> handle_modem_error(error)
    end
  end

  defp health_check_impl do
    base_url = config(:modem_base_url, "http://192.168.8.1")
    url = "#{base_url}/api/monitoring/status"

    with {:ok, {session_id, token}} <- get_session_token(),
         {:ok, response} <- send_authenticated_get(url, session_id, token),
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
    try do
      message_id = xpath(body, ~x"//response/message_id/text()"s)

      if message_id && message_id != "" do
        {:ok, message_id}
      else
        {:error, :invalid_response}
      end
    rescue
      _ -> {:error, :parse_error}
    end
  end

  defp parse_list_sms_response(body) do
    try do
      messages =
        xpath(body, ~x"//response/messages/message"l,
          index: ~x"./index/text()"s,
          phone: ~x"./phone/text()"s,
          content: ~x"./content/text()"s,
          date: ~x"./date/text()"s,
          status: ~x"./status/text()"s
        )
        |> Enum.map(&parse_message_struct/1)

      {:ok, messages}
    rescue
      _ -> {:error, :parse_error}
    end
  end

  defp parse_message_struct(msg_data) do
    %{
      index: safe_to_integer(msg_data.index),
      phone: msg_data.phone,
      content: msg_data.content,
      date: msg_data.date,
      status: msg_data.status
    }
  end

  defp parse_get_status_response(body) do
    try do
      status_str = xpath(body, ~x"//response/status/text()"s)
      status_atom = parse_status_string(status_str)
      {:ok, status_atom}
    rescue
      _ -> {:error, :parse_error}
    end
  end

  defp parse_health_check_response(body) do
    try do
      health_info = %{
        signal_strength: xpath(body, ~x"//response/signal_strength/text()"s) |> safe_to_integer(),
        network_type: xpath(body, ~x"//response/network_type/text()"s),
        network_name: xpath(body, ~x"//response/network_name/text()"s),
        battery_level: xpath(body, ~x"//response/battery_level/text()"s) |> safe_to_integer(),
        connection_status: xpath(body, ~x"//response/connection_status/text()"s)
      }

      {:ok, health_info}
    rescue
      _ -> {:error, :parse_error}
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
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp safe_to_integer(int) when is_integer(int), do: int
  defp safe_to_integer(_), do: nil

  # ============================================================================
  # Circuit Breaker Logic
  # ============================================================================

  defp circuit_breaker_open?() do
    case :persistent_term.get(@circuit_breaker_key, nil) do
      %CircuitBreaker{state: :open, opened_at: opened_at} ->
        elapsed = System.monotonic_time(:millisecond) - opened_at

        if elapsed > @backoff_duration do
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
