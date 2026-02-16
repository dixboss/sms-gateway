defmodule SmsGatewayWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug for API Key authentication and rate limiting.

  Authentication:
  - Extracts API key from X-API-Key header
  - Validates key against database (prefix lookup + bcrypt verification)
  - Loads ApiKey resource into conn.assigns.current_api_key
  - Returns 401 if invalid or missing

  Rate Limiting:
  - Checks if API key has exceeded rate limit
  - Rate limit configured per API key (nullable, default from config)
  - Returns 429 Too Many Requests if exceeded
  - Adds rate limit headers to response:
    * X-RateLimit-Limit: max requests per hour
    * X-RateLimit-Remaining: remaining requests
    * X-RateLimit-Reset: timestamp when limit resets

  Usage:
      pipeline :api_authenticated do
        plug :accepts, ["json"]
        plug SmsGatewayWeb.Plugs.ApiAuth
      end
  """

  import Plug.Conn
  require Logger

  alias SmsGateway.Sms.ApiKey

  @header_name "x-api-key"
  # requests per hour
  @default_rate_limit 100

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, @header_name) do
      [api_key] ->
        authenticate(conn, api_key)

      [] ->
        unauthorized(conn, "Missing API key")

      _ ->
        unauthorized(conn, "Multiple API keys provided")
    end
  end

  # ============================================================================
  # Authentication
  # ============================================================================

  defp authenticate(conn, api_key) do
    # Extract prefix (e.g., "sk_live_abc123...")
    prefix = extract_prefix(api_key)

    case load_api_key_by_prefix(prefix) do
      {:ok, key_record} ->
        if verify_key(api_key, key_record.key_hash) do
          conn
          |> assign(:current_api_key, key_record)
          |> check_rate_limit()
          |> touch_last_used(key_record)
        else
          unauthorized(conn, "Invalid API key")
        end

      {:error, _} ->
        unauthorized(conn, "Invalid API key")
    end
  end

  defp extract_prefix(api_key) do
    # Prefix is the first 20 characters (e.g., "sk_live_abc123456789")
    String.slice(api_key, 0..19)
  end

  defp load_api_key_by_prefix(prefix) do
    case Ash.read(ApiKey, action: :by_prefix, actor: nil, input: %{prefix: prefix}) do
      {:ok, key_record} when not is_nil(key_record) ->
        {:ok, key_record}

      {:ok, nil} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("Failed to load API key: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp verify_key(api_key, key_hash) do
    Bcrypt.verify_pass(api_key, key_hash)
  rescue
    _ -> false
  end

  # ============================================================================
  # Rate Limiting
  # ============================================================================

  defp check_rate_limit(conn) do
    api_key = conn.assigns.current_api_key
    rate_limit = api_key.rate_limit || get_default_rate_limit()

    # Get request count for this API key in the current hour
    request_count = get_request_count(api_key.id)

    if request_count >= rate_limit do
      rate_limit_exceeded(conn, rate_limit, 0)
    else
      # Increment request count
      increment_request_count(api_key.id)

      remaining = rate_limit - request_count - 1
      reset_time = get_reset_time()

      conn
      |> put_resp_header("x-ratelimit-limit", to_string(rate_limit))
      |> put_resp_header("x-ratelimit-remaining", to_string(remaining))
      |> put_resp_header("x-ratelimit-reset", to_string(reset_time))
    end
  end

  defp get_request_count(api_key_id) do
    # Use ETS table for rate limiting (simple in-memory counter)
    # In production, consider Redis for distributed rate limiting
    table_name = :api_rate_limit

    # Ensure table exists
    unless :ets.whereis(table_name) != :undefined do
      :ets.new(table_name, [:named_table, :public, :set])
    end

    current_hour = DateTime.utc_now() |> DateTime.to_unix(:second) |> div(3600)
    key = {api_key_id, current_hour}

    case :ets.lookup(table_name, key) do
      [{^key, count}] -> count
      [] -> 0
    end
  end

  defp increment_request_count(api_key_id) do
    table_name = :api_rate_limit
    current_hour = DateTime.utc_now() |> DateTime.to_unix(:second) |> div(3600)
    key = {api_key_id, current_hour}

    :ets.update_counter(table_name, key, {2, 1}, {key, 0})
  end

  defp get_reset_time do
    # Return Unix timestamp for the start of next hour
    now = DateTime.utc_now()
    next_hour = DateTime.add(now, 3600 - rem(DateTime.to_unix(now, :second), 3600), :second)
    DateTime.to_unix(next_hour, :second)
  end

  defp get_default_rate_limit do
    Application.get_env(:sms_gateway, :default_rate_limit, @default_rate_limit)
  end

  # ============================================================================
  # Response Helpers
  # ============================================================================

  defp unauthorized(conn, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: message}))
    |> halt()
  end

  defp rate_limit_exceeded(conn, limit, remaining) do
    reset_time = get_reset_time()

    conn
    |> put_resp_header("x-ratelimit-limit", to_string(limit))
    |> put_resp_header("x-ratelimit-remaining", to_string(remaining))
    |> put_resp_header("x-ratelimit-reset", to_string(reset_time))
    |> put_resp_content_type("application/json")
    |> send_resp(
      429,
      Jason.encode!(%{
        error: "Rate limit exceeded",
        limit: limit,
        reset_at: reset_time
      })
    )
    |> halt()
  end

  # ============================================================================
  # Update Last Used
  # ============================================================================

  defp touch_last_used(conn, api_key) do
    # Update last_used_at asynchronously (don't block the request)
    Task.start(fn ->
      case Ash.update(api_key, %{}, action: :touch_last_used) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Failed to update last_used_at: #{inspect(reason)}")
      end
    end)

    conn
  end
end
