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
      |> assign(:created_key, nil)
      |> assign(:loading_action, nil)
      |> assign(:delete_confirm_key, nil)
      |> assign(:toast_message, nil)
      |> assign(:search_query, "")
      |> assign(:filter_status, :all)
      |> assign(:page, 1)
      |> assign(:per_page, 10)
      |> assign(:total_count, 0)
      |> load_api_keys()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form, created_key: nil)}
  end

  @impl true
  def handle_event("create", %{"api_key" => params}, socket) do
    socket = assign(socket, loading_action: :creating)

    case create_api_key(params) do
      {:ok, api_key} ->
        # Extract the raw key before it's hashed (only shown once)
        raw_key = api_key.__metadata__.raw_key

        socket =
          socket
          |> assign(:created_key, raw_key)
          |> assign(:show_form, true)
          |> assign(:loading_action, nil)
          |> load_api_keys()
          |> show_toast(:success, "API Key created successfully!")
          |> put_flash(
            :info,
            "API Key created successfully! Save it now, it won't be shown again."
          )

        {:noreply, socket}

      {:error, changeset} ->
        error_msg = "Failed to create API Key: #{format_errors(changeset)}"

        socket =
          socket
          |> assign(:loading_action, nil)
          |> show_toast(:error, error_msg)
          |> put_flash(:error, error_msg)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    socket = assign(socket, loading_action: {:toggling, id})

    case get_api_key(id) do
      {:ok, api_key} ->
        case toggle_active(api_key) do
          {:ok, _updated} ->
            socket =
              socket
              |> assign(:loading_action, nil)
              |> load_api_keys()
              |> show_toast(:success, "API Key updated successfully")

            {:noreply, socket}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:loading_action, nil)
             |> show_toast(:error, "Failed to update API Key")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:loading_action, nil)
         |> show_toast(:error, "API Key not found")}
    end
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:page, 1)
     |> load_api_keys()}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    status_atom = String.to_existing_atom(status)

    {:noreply,
     socket
     |> assign(:filter_status, status_atom)
     |> assign(:page, 1)
     |> load_api_keys()}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    max_page = max(1, ceil(socket.assigns.total_count / socket.assigns.per_page))
    page = max(1, min(page, max_page))

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_api_keys()}
  end

  @impl true
  def handle_event("show_delete_modal", %{"id" => id}, socket) do
    {:noreply, assign(socket, delete_confirm_key: id)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    socket = assign(socket, loading_action: {:deleting, id})

    case get_api_key(id) do
      {:ok, api_key} ->
        case Ash.destroy(api_key) do
          :ok ->
            socket =
              socket
              |> assign(:loading_action, nil)
              |> assign(:delete_confirm_key, nil)
              |> load_api_keys()
              |> show_toast(:success, "API Key deleted successfully")

            {:noreply, socket}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:loading_action, nil)
             |> show_toast(:error, "Failed to delete API Key")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:loading_action, nil)
         |> show_toast(:error, "API Key not found")}
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

  @impl true
  def handle_info(:dismiss_toast, socket) do
    {:noreply, assign(socket, toast_message: nil)}
  end

  # Private functions

  defp load_api_keys(socket) do
    query = ApiKey

    # Apply search filter
    query =
      if socket.assigns.search_query != "" do
        search = "%#{socket.assigns.search_query}%"

        Ash.Query.filter(
          query,
          fragment("? ILIKE ?", name, ^search) or
            fragment("? ILIKE ?", key_prefix, ^search)
        )
      else
        query
      end

    # Apply status filter
    query =
      case socket.assigns.filter_status do
        :active -> Ash.Query.filter(query, is_active == true)
        :inactive -> Ash.Query.filter(query, is_active == false)
        :all -> query
      end

    # Apply sorting
    query = Ash.Query.sort(query, inserted_at: :desc)

    # Get total count before pagination
    total_count = query |> Ash.count!()

    # Apply pagination
    offset = (socket.assigns.page - 1) * socket.assigns.per_page

    query =
      query
      |> Ash.Query.limit(socket.assigns.per_page)
      |> Ash.Query.offset(offset)

    api_keys = Ash.read!(query)

    socket
    |> assign(:api_keys, api_keys)
    |> assign(:total_count, total_count)
  end

  defp create_api_key(params) do
    # Parse rate_limit as integer
    params =
      params
      |> Map.update("rate_limit", 100, &parse_integer/1)

    # Use the create_key action which generates key_hash and key_prefix internally
    case Ash.create(ApiKey, params, action: :create_key) do
      {:ok, api_key} ->
        # Broadcast event for real-time updates
        Phoenix.PubSub.broadcast(
          SmsGateway.PubSub,
          "api_keys",
          {:api_key_created, api_key}
        )

        # Show the key prefix as placeholder (actual key is already hashed)
        {:ok,
         Map.put(api_key, :__metadata__, %{
           raw_key: api_key.key_prefix <> "... (key was generated)"
         })}

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

  defp show_toast(socket, type, message) do
    # Schedule auto-dismiss after 3 seconds
    Process.send_after(self(), :dismiss_toast, 3000)

    assign(socket, toast_message: %{type: type, message: message})
  end

  defp pagination_range(_current, total) when total <= 7 do
    1..total
  end

  defp pagination_range(current, total) do
    cond do
      current <= 4 -> 1..5
      current >= total - 3 -> (total - 4)..total
      true -> (current - 2)..(current + 2)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header -->
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-base-content">API Keys Management</h1>
        <p class="mt-2 text-sm text-base-content/60">
          Manage API keys for accessing the SMS Gateway API
        </p>
      </div>

      <!-- Search and filters -->
      <div class="card bg-base-100 shadow-sm border border-base-300 mb-6">
        <div class="card-body p-4">
          <div class="flex flex-col sm:flex-row gap-3">
            <!-- Search input -->
            <div class="flex-1">
              <label class="input input-bordered flex items-center gap-2">
                <svg class="w-4 h-4 opacity-70" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
                </svg>
                <input
                  type="text"
                  phx-change="search"
                  phx-debounce="300"
                  name="query"
                  value={@search_query}
                  placeholder="Search by name or prefix..."
                  class="grow"
                />
              </label>
            </div>

            <!-- Status filter -->
            <div class="join">
              <button
                phx-click="filter_status"
                phx-value-status="all"
                class={["btn join-item", if(@filter_status == :all, do: "btn-active")]}
              >
                All
              </button>
              <button
                phx-click="filter_status"
                phx-value-status="active"
                class={["btn join-item", if(@filter_status == :active, do: "btn-active")]}
              >
                Active
              </button>
              <button
                phx-click="filter_status"
                phx-value-status="inactive"
                class={["btn join-item", if(@filter_status == :inactive, do: "btn-active")]}
              >
                Inactive
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Flash messages -->
      <div :if={@flash["info"]} class="alert alert-success mb-4">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
        </svg>
        <span><%= @flash["info"] %></span>
      </div>
      <div :if={@flash["error"]} class="alert alert-error mb-4">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/>
        </svg>
        <span><%= @flash["error"] %></span>
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
                class="ml-2 inline-flex items-center gap-1 text-yellow-800 hover:text-yellow-900 font-medium"
                phx-click={JS.dispatch("phx:copy", to: "#created-key-value")}
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
                </svg>
                Copy
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
          class={["btn", if(@show_form, do: "btn-ghost", else: "btn-primary")]}
        >
          <svg :if={!@show_form} class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
          </svg>
          <%= if @show_form, do: "Cancel", else: "Create New API Key" %>
        </button>
      </div>

      <!-- Create Form -->
      <div :if={@show_form} class="card bg-base-100 shadow-sm border border-base-300 mb-8">
        <div class="card-body">
          <h2 class="card-title text-lg">Create New API Key</h2>

          <form phx-submit="create" class="space-y-4">
            <fieldset class="fieldset">
              <legend class="fieldset-legend">Key Information</legend>

              <label class="form-control w-full">
                <div class="label">
                  <span class="label-text">Name <span class="text-error">*</span></span>
                </div>
                <input
                  type="text"
                  name="api_key[name]"
                  id="name"
                  required
                  class="input input-bordered w-full"
                  placeholder="e.g., Mobile App, Zabbix Alerts"
                />
                <div class="label">
                  <span class="label-text-alt text-base-content/60">
                    A descriptive name to identify this API key
                  </span>
                </div>
              </label>

              <label class="form-control w-full">
                <div class="label">
                  <span class="label-text">Rate Limit (SMS/hour)</span>
                </div>
                <input
                  type="number"
                  name="api_key[rate_limit]"
                  id="rate_limit"
                  value="100"
                  min="1"
                  max="10000"
                  class="input input-bordered w-full"
                />
                <div class="label">
                  <span class="label-text-alt text-base-content/60">
                    Maximum number of SMS per hour
                  </span>
                </div>
              </label>
            </fieldset>

            <div class="card-actions justify-end gap-2">
              <button
                type="button"
                phx-click="toggle_form"
                class="btn btn-ghost"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="btn btn-primary"
                disabled={@loading_action == :creating}
              >
                <span :if={@loading_action == :creating} class="loading loading-spinner loading-sm"></span>
                <svg :if={@loading_action != :creating} class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"/>
                </svg>
                Generate API Key
              </button>
            </div>
          </form>
        </div>
      </div>

      <!-- API Keys List -->
      <div class="bg-base-100 shadow overflow-hidden sm:rounded-lg border border-base-300">
        <div class="px-4 py-5 sm:px-6 border-b border-base-300">
          <h2 class="text-lg font-medium text-base-content">
            API Keys (<%= length(@api_keys) %>)
          </h2>
        </div>

        <div :if={Enum.empty?(@api_keys)} class="px-4 py-12 text-center">
          <svg
            class="mx-auto h-12 w-12 text-base-content/40"
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
          <h3 class="mt-2 text-sm font-medium text-base-content">No API keys</h3>
          <p class="mt-1 text-sm text-base-content/50">
            Get started by creating a new API key.
          </p>
        </div>

        <ul :if={!Enum.empty?(@api_keys)} role="list" class="divide-y divide-base-300">
          <li :for={api_key <- @api_keys} class="px-4 py-4 sm:px-6 hover:bg-base-200">
            <div class="flex items-center justify-between">
              <div class="flex-1 min-w-0">
                <div class="flex items-center space-x-3">
                  <span class={["badge", if(api_key.is_active, do: "badge-success", else: "badge-ghost")]}>
                    <%= if api_key.is_active, do: "Active", else: "Inactive" %>
                  </span>
                  <h3 class="text-sm font-medium text-base-content truncate">
                    <%= api_key.name %>
                  </h3>
                </div>

                <div class="mt-2 flex items-center space-x-4 text-sm text-base-content/50">
                  <div class="flex items-center">
                    <code class="text-xs bg-base-200 px-2 py-1 rounded font-mono">
                      <%= api_key.key_prefix %>...
                    </code>
                  </div>
                  <div>
                    Rate: <%= api_key.rate_limit || "Unlimited" %> SMS/h
                  </div>
                  <div>
                    Last used: <%= time_ago(api_key.last_used_at) %>
                  </div>
                  <div>
                    Created: <%= format_datetime(api_key.inserted_at) %>
                  </div>
                </div>
              </div>

              <div class="flex items-center gap-2">
                <button
                  phx-click="toggle_active"
                  phx-value-id={api_key.id}
                  class={["btn btn-sm", if(api_key.is_active, do: "btn-ghost", else: "btn-success")]}
                  disabled={@loading_action == {:toggling, api_key.id}}
                >
                  <span :if={@loading_action == {:toggling, api_key.id}} class="loading loading-spinner loading-xs"></span>
                  <%= if api_key.is_active, do: "Disable", else: "Enable" %>
                </button>

                <button
                  phx-click="show_delete_modal"
                  phx-value-id={api_key.id}
                  class="btn btn-sm btn-error btn-outline"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                  </svg>
                  Delete
                </button>
              </div>
            </div>
          </li>
        </ul>
      </div>

      <!-- Pagination -->
      <div :if={@total_count > @per_page} class="card bg-base-100 shadow-sm border border-base-300 mt-6">
        <div class="card-body p-4">
          <div class="flex items-center justify-between">
            <span class="text-sm text-base-content/60">
              Showing <%= (@page - 1) * @per_page + 1 %>-<%= min(@page * @per_page, @total_count) %> of <%= @total_count %> keys
            </span>

            <div class="join">
              <button
                phx-click="paginate"
                phx-value-page={@page - 1}
                class="join-item btn btn-sm"
                disabled={@page == 1}
              >
                «
              </button>

              <%= for page_num <- pagination_range(@page, ceil(@total_count / @per_page)) do %>
                <button
                  phx-click="paginate"
                  phx-value-page={page_num}
                  class={["join-item btn btn-sm", if(@page == page_num, do: "btn-active")]}
                >
                  <%= page_num %>
                </button>
              <% end %>

              <button
                phx-click="paginate"
                phx-value-page={@page + 1}
                class="join-item btn btn-sm"
                disabled={@page >= ceil(@total_count / @per_page)}
              >
                »
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Modal confirmation delete -->
      <dialog :if={@delete_confirm_key} id="delete-confirm-modal" class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Delete API Key</h3>
          <p class="py-4">
            Are you sure you want to delete this API key?
            <strong class="text-error">This action cannot be undone.</strong>
          </p>
          <div class="modal-action">
            <button
              phx-click="show_delete_modal"
              phx-value-id=""
              class="btn btn-ghost"
            >
              Cancel
            </button>
            <button
              phx-click="delete"
              phx-value-id={@delete_confirm_key}
              class="btn btn-error"
              disabled={@loading_action == {:deleting, @delete_confirm_key}}
            >
              <span :if={@loading_action == {:deleting, @delete_confirm_key}} class="loading loading-spinner loading-sm"></span>
              Delete
            </button>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button phx-click="show_delete_modal" phx-value-id="">close</button>
        </form>
      </dialog>

      <!-- Toast notifications -->
      <div :if={@toast_message} class="toast toast-top toast-end">
        <div class={[
          "alert",
          case @toast_message.type do
            :success -> "alert-success"
            :error -> "alert-error"
            :warning -> "alert-warning"
            _ -> "alert-info"
          end
        ]}>
          <span><%= @toast_message.message %></span>
        </div>
      </div>
    </div>
    """
  end
end
