defmodule SmsGatewayWeb.Api.V1.MessageController do
  @moduledoc """
  REST API controller for SMS messages.

  Endpoints:
  - POST /api/v1/messages - Send an SMS
  - GET /api/v1/messages - List SMS messages
  - GET /api/v1/messages/:id - Get a specific message

  All endpoints require authentication via X-API-Key header.
  """

  use SmsGatewayWeb, :controller

  require Logger
  require Ash.Query

  alias SmsGateway.Sms.Message

  @doc """
  POST /api/v1/messages

  Create and send an SMS message.

  Request body:
  {
    "phone": "+33612345678",
    "content": "Your verification code: 123456"
  }

  Response 201:
  {
    "id": "uuid",
    "direction": "outgoing",
    "phone": "+33612345678",
    "content": "...",
    "status": "pending",
    "inserted_at": "2026-02-16T10:30:00Z"
  }

  Errors:
  - 400: Validation error (invalid phone, content too long)
  - 401: Invalid API key
  - 429: Rate limit exceeded
  - 503: Modem unavailable (circuit breaker open)
  """
  def create(conn, %{"phone" => phone, "content" => content}) do
    api_key = conn.assigns.current_api_key

    case Ash.create(
           Message,
           %{
             phone_number: phone,
             content: content,
             api_key_id: api_key.id
           },
           action: :create_outgoing
         ) do
      {:ok, message} ->
        conn
        |> put_status(:created)
        |> json(format_message(message))

      {:error, %Ash.Error.Invalid{} = error} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Validation failed", details: format_ash_error(error)})

      {:error, error} ->
        Logger.error("Failed to create message: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to create message"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required fields: phone, content"})
  end

  @doc """
  GET /api/v1/messages

  List SMS messages with optional filtering.

  Query params:
  - direction: "outgoing" | "incoming"
  - status: "pending" | "queued" | "sending" | "sent" | "delivered" | "failed" | "received"
  - phone: "+33612345678"
  - limit: 50 (default)
  - offset: 0 (default)

  Response 200:
  {
    "data": [
      {
        "id": "uuid",
        "direction": "outgoing",
        "phone": "+33612345678",
        "content": "...",
        "status": "delivered",
        "sent_at": "...",
        "delivered_at": "..."
      }
    ],
    "meta": {
      "limit": 50,
      "offset": 0
    }
  }
  """
  def index(conn, params) do
    api_key = conn.assigns.current_api_key
    limit = parse_int(params["limit"], 50)
    offset = parse_int(params["offset"], 0)

    # Build base query filtering by API key ownership
    base_query =
      Message
      |> Ash.Query.for_read(:list, %{}, actor: api_key)
      |> Ash.Query.limit(limit)
      |> Ash.Query.offset(offset)
      |> Ash.Query.sort(inserted_at: :desc)

    # Apply filters including ownership
    query =
      base_query
      |> apply_filter_by_api_key(api_key.id)
      |> apply_filters(params)

    case Ash.read(query) do
      {:ok, messages} ->
        conn
        |> json(%{
          data: Enum.map(messages, &format_message/1),
          meta: %{
            limit: limit,
            offset: offset
          }
        })

      {:error, error} ->
        Logger.error("Failed to list messages: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to list messages"})
    end
  end

  @doc """
  GET /api/v1/messages/:id

  Get a specific message by ID.

  Response 200:
  {
    "id": "uuid",
    "direction": "outgoing",
    "phone": "+33612345678",
    "content": "...",
    "status": "delivered",
    "modem_message_id": "12345",
    "sent_at": "...",
    "delivered_at": "...",
    "inserted_at": "...",
    "updated_at": "..."
  }

  Errors:
  - 404: Message not found or not owned by this API key
  """
  def show(conn, %{"id" => id}) do
    api_key = conn.assigns.current_api_key

    case Ash.get(Message, id, actor: api_key) do
      {:ok, message} ->
        # Verify ownership
        if message.api_key_id == api_key.id do
          conn
          |> json(format_message(message))
        else
          conn
          |> put_status(:not_found)
          |> json(%{error: "Message not found"})
        end

      {:error, %Ash.Error.Query.NotFound{}} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Message not found"})

      {:error, error} ->
        Logger.error("Failed to get message: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to get message"})
    end
  end

  # ============================================================================
  # Filtering
  # ============================================================================

  defp apply_filter_by_api_key(query, api_key_id) do
    Ash.Query.filter(query, api_key_id: api_key_id)
  end

  defp apply_filters(query, params) do
    query
    |> filter_by_direction(params["direction"])
    |> filter_by_status(params["status"])
    |> filter_by_phone(params["phone"])
  end

  defp filter_by_direction(query, nil), do: query

  defp filter_by_direction(query, direction)
       when direction in ["outgoing", "incoming"] do
    Ash.Query.filter(query, direction: String.to_atom(direction))
  end

  defp filter_by_direction(query, _), do: query

  defp filter_by_status(query, nil), do: query

  defp filter_by_status(query, status)
       when status in [
              "pending",
              "queued",
              "sending",
              "sent",
              "delivered",
              "failed",
              "received"
            ] do
    Ash.Query.filter(query, status: String.to_atom(status))
  end

  defp filter_by_status(query, _), do: query

  defp filter_by_phone(query, nil), do: query

  defp filter_by_phone(query, phone_value) do
    Ash.Query.filter(query, phone_number: phone_value)
  end

  # ============================================================================
  # Formatting
  # ============================================================================

  defp format_message(message) do
    %{
      id: message.id,
      direction: message.direction,
      phone: message.phone_number,
      content: message.content,
      status: message.status,
      modem_message_id: message.modem_message_id,
      error_message: message.error_message,
      sent_at: format_datetime(message.sent_at),
      delivered_at: format_datetime(message.delivered_at),
      received_at: format_datetime(message.received_at),
      inserted_at: format_datetime(message.inserted_at),
      updated_at: format_datetime(message.updated_at)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(datetime), do: DateTime.to_iso8601(datetime)

  defp format_ash_error(%Ash.Error.Invalid{errors: errors}) do
    Enum.map(errors, fn error ->
      %{
        field: error.field || "unknown",
        message: Exception.message(error)
      }
    end)
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default
end
