defmodule SmsGatewayWeb.Admin.ApiKeysLive do
  use SmsGatewayWeb, :live_view

  require Ash.Query

  alias SmsGateway.Sms.ApiKey

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to changes for real-time updates
      Phoenix.PubSub.subscribe(SmsGateway.PubSub, "api_keys")
    end

    socket =
      socket
      |> assign(:page_title, "API Keys Management")
      |> assign(:show_form, false)
      |> assign(:form_data, %{"name" => "", "rate_limit" => "100"})
      |> assign(:created_key, nil)
      |> load_api_keys()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form, created_key: nil)}
  end

  @impl true
  def handle_event("create", %{"api_key" => params}, socket) do
    case create_api_key(params) do
      {:ok, api_key} ->
        # Extract the raw key before it's hashed (only shown once)
        raw_key = api_key.__metadata__.raw_key

        socket =
          socket
          |> assign(:created_key, raw_key)
          |> assign(:show_form, true)
          |> load_api_keys()
          |> put_flash(
            :info,
            "API Key created successfully! Save it now, it won't be shown again."
          )

        {:noreply, socket}

      {:error, changeset} ->
        socket =
          socket
          |> put_flash(:error, "Failed to create API Key: #{format_errors(changeset)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    case get_api_key(id) do
      {:ok, api_key} ->
        case toggle_active(api_key) do
          {:ok, _updated} ->
            socket =
              socket
              |> load_api_keys()
              |> put_flash(:info, "API Key updated successfully")

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update API Key")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "API Key not found")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case get_api_key(id) do
      {:ok, api_key} ->
        case Ash.destroy(api_key) do
          :ok ->
            socket =
              socket
              |> load_api_keys()
              |> put_flash(:info, "API Key deleted successfully")

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete API Key")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "API Key not found")}
    end
  end

  @impl true
  def handle_info({:api_key_created, _api_key}, socket) do
    {:noreply, load_api_keys(socket)}
  end

  @impl true
  def handle_info({:api_key_updated, _api_key}, socket) do
    {:noreply, load_api_keys(socket)}
  end

  # Private functions

  defp load_api_keys(socket) do
    api_keys =
      ApiKey
      |> Ash.read!()
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    assign(socket, :api_keys, api_keys)
  end

  defp create_api_key(params) do
    # Generate random key
    raw_key =
      ("sk_live_" <> :crypto.strong_rand_bytes(32)) |> Base.encode64() |> binary_part(0, 32)

    # Hash the key
    key_hash = Bcrypt.hash_pwd_salt(raw_key)

    # Get prefix (first 12 chars for display)
    key_prefix = String.slice(raw_key, 0, 12)

    params =
      params
      |> Map.put("key_hash", key_hash)
      |> Map.put("key_prefix", key_prefix)
      |> Map.update("rate_limit", 100, &parse_integer/1)

    case Ash.create(ApiKey, params) do
      {:ok, api_key} ->
        # Store raw key in metadata so we can show it once
        api_key = Map.put(api_key, :__metadata__, %{raw_key: raw_key})

        # Broadcast event for real-time updates
        Phoenix.PubSub.broadcast(
          SmsGateway.PubSub,
          "api_keys",
          {:api_key_created, api_key}
        )

        {:ok, api_key}

      error ->
        error
    end
  end

  defp get_api_key(id) do
    ApiKey
    |> Ash.get(id)
  end

  defp toggle_active(api_key) do
    case Ash.update(api_key, %{is_active: !api_key.is_active}) do
      {:ok, updated} ->
        Phoenix.PubSub.broadcast(
          SmsGateway.PubSub,
          "api_keys",
          {:api_key_updated, updated}
        )

        {:ok, updated}

      error ->
        error
    end
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 100
    end
  end

  defp parse_integer(value) when is_integer(value), do: value
  defp parse_integer(_), do: 100

  defp format_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp time_ago(nil), do: "Never"

  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header -->
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">API Keys Management</h1>
        <p class="mt-2 text-sm text-gray-600">
          Manage API keys for accessing the SMS Gateway API
        </p>
      </div>

      <!-- Flash messages -->
      <div :if={@flash["info"]} class="mb-4 bg-green-50 border border-green-200 text-green-800 px-4 py-3 rounded">
        <%= @flash["info"] %>
      </div>
      <div :if={@flash["error"]} class="mb-4 bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded">
        <%= @flash["error"] %>
      </div>

      <!-- Created Key Display (only shown once) -->
      <div :if={@created_key} class="mb-6 bg-yellow-50 border-l-4 border-yellow-400 p-4">
        <div class="flex">
          <div class="flex-shrink-0">
            <svg class="h-5 w-5 text-yellow-400" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
            </svg>
          </div>
          <div class="ml-3 flex-1">
            <p class="text-sm font-medium text-yellow-800">
              Save this API Key now! It won't be shown again.
            </p>
            <div class="mt-2 text-sm text-yellow-700">
              <code class="bg-yellow-100 px-2 py-1 rounded font-mono text-xs">
                <%= @created_key %>
              </code>
              <button
                type="button"
                class="ml-2 text-yellow-800 hover:text-yellow-900"
                phx-click={JS.dispatch("phx:copy", to: "#created-key-value")}
              >
                📋 Copy
              </button>
              <input type="hidden" id="created-key-value" value={@created_key} />
            </div>
          </div>
        </div>
      </div>

      <!-- Create Button -->
      <div class="mb-6">
        <button
          phx-click="toggle_form"
          class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
        >
          <%= if @show_form, do: "❌ Cancel", else: "➕ Create New API Key" %>
        </button>
      </div>

      <!-- Create Form -->
      <div :if={@show_form} class="mb-8 bg-white shadow rounded-lg p-6">
        <h2 class="text-lg font-medium text-gray-900 mb-4">Create New API Key</h2>

        <form phx-submit="create">
          <div class="space-y-4">
            <div>
              <label for="name" class="block text-sm font-medium text-gray-700">
                Name <span class="text-red-500">*</span>
              </label>
              <input
                type="text"
                name="api_key[name]"
                id="name"
                required
                class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                placeholder="e.g., Mobile App, Zabbix Alerts"
              />
              <p class="mt-1 text-xs text-gray-500">
                A descriptive name to identify this API key
              </p>
            </div>

            <div>
              <label for="rate_limit" class="block text-sm font-medium text-gray-700">
                Rate Limit (SMS/hour)
              </label>
              <input
                type="number"
                name="api_key[rate_limit]"
                id="rate_limit"
                value="100"
                min="1"
                max="10000"
                class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
              />
              <p class="mt-1 text-xs text-gray-500">
                Maximum number of SMS per hour (leave empty for unlimited)
              </p>
            </div>

            <div class="flex justify-end space-x-3">
              <button
                type="button"
                phx-click="toggle_form"
                class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                🔑 Generate API Key
              </button>
            </div>
          </div>
        </form>
      </div>

      <!-- API Keys List -->
      <div class="bg-white shadow overflow-hidden sm:rounded-lg">
        <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
          <h2 class="text-lg font-medium text-gray-900">
            API Keys (<%= length(@api_keys) %>)
          </h2>
        </div>

        <div :if={Enum.empty?(@api_keys)} class="px-4 py-12 text-center">
          <svg
            class="mx-auto h-12 w-12 text-gray-400"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"
            />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No API keys</h3>
          <p class="mt-1 text-sm text-gray-500">
            Get started by creating a new API key.
          </p>
        </div>

        <ul :if={!Enum.empty?(@api_keys)} role="list" class="divide-y divide-gray-200">
          <li :for={api_key <- @api_keys} class="px-4 py-4 sm:px-6 hover:bg-gray-50">
            <div class="flex items-center justify-between">
              <div class="flex-1 min-w-0">
                <div class="flex items-center space-x-3">
                  <span class={[
                    "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                    if(api_key.is_active,
                      do: "bg-green-100 text-green-800",
                      else: "bg-gray-100 text-gray-800"
                    )
                  ]}>
                    <%= if api_key.is_active, do: "✅ Active", else: "⏸️ Inactive" %>
                  </span>
                  <h3 class="text-sm font-medium text-gray-900 truncate">
                    <%= api_key.name %>
                  </h3>
                </div>

                <div class="mt-2 flex items-center space-x-4 text-sm text-gray-500">
                  <div class="flex items-center">
                    <code class="text-xs bg-gray-100 px-2 py-1 rounded font-mono">
                      <%= api_key.key_prefix %>...
                    </code>
                  </div>
                  <div>
                    📊 Rate: <%= api_key.rate_limit || "Unlimited" %> SMS/h
                  </div>
                  <div>
                    🕐 Last used: <%= time_ago(api_key.last_used_at) %>
                  </div>
                  <div>
                    📅 Created: <%= format_datetime(api_key.inserted_at) %>
                  </div>
                </div>
              </div>

              <div class="flex items-center space-x-2">
                <button
                  phx-click="toggle_active"
                  phx-value-id={api_key.id}
                  class={[
                    "inline-flex items-center px-3 py-1 border text-sm font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500",
                    if(api_key.is_active,
                      do:
                        "border-gray-300 text-gray-700 bg-white hover:bg-gray-50",
                      else:
                        "border-green-300 text-green-700 bg-green-50 hover:bg-green-100"
                    )
                  ]}
                >
                  <%= if api_key.is_active, do: "⏸️ Disable", else: "▶️ Enable" %>
                </button>

                <button
                  phx-click="delete"
                  phx-value-id={api_key.id}
                  data-confirm="Are you sure you want to delete this API key? This action cannot be undone."
                  class="inline-flex items-center px-3 py-1 border border-red-300 text-sm font-medium rounded-md text-red-700 bg-red-50 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                >
                  🗑️ Delete
                </button>
              </div>
            </div>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end
