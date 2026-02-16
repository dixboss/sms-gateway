defmodule SmsGateway.Modem.Poller do
  @moduledoc """
  GenServer that periodically polls the modem for incoming SMS messages.

  Polls the modem inbox every N seconds (default: 30s), detects new messages,
  and creates Message records in the database for each new SMS received.

  Tracks the last seen message index to avoid duplicates.
  """

  use GenServer

  require Logger

  # 30 seconds (configurable)
  @poll_interval 30_000

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_last_seen_index do
    GenServer.call(__MODULE__, :get_last_seen_index)
  rescue
    _ -> nil
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(opts) do
    Logger.info("Modem.Poller starting")

    poll_interval = Keyword.get(opts, :poll_interval, @poll_interval)

    state = %{
      poll_interval: poll_interval,
      last_seen_index: load_last_seen_index(),
      poll_timer: schedule_poll(poll_interval)
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    Logger.debug("Polling modem for incoming SMS")

    new_state =
      case SmsGateway.Modem.Client.list_sms(1) do
        {:ok, messages} ->
          process_new_messages(messages, state)

        {:error, reason} ->
          Logger.warning("Failed to poll modem: #{inspect(reason)}")
          state
      end

    {:noreply, %{new_state | poll_timer: schedule_poll(new_state.poll_interval)}}
  end

  @impl GenServer
  def handle_call(:get_last_seen_index, _from, state) do
    {:reply, state.last_seen_index, state}
  end

  # ============================================================================
  # Polling Logic
  # ============================================================================

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp process_new_messages(messages, state) do
    last_seen = state.last_seen_index || 0

    new_messages =
      Enum.filter(messages, fn msg ->
        msg_index = msg.index || 0
        msg_index > last_seen
      end)

    if Enum.empty?(new_messages) do
      state
    else
      Logger.info("Found #{Enum.count(new_messages)} new SMS messages")

      Enum.each(new_messages, &create_message_record/1)

      # Update last seen index
      new_last_seen =
        new_messages
        |> Enum.map(& &1.index)
        |> Enum.max(fn -> last_seen end)

      save_last_seen_index(new_last_seen)

      %{state | last_seen_index: new_last_seen}
    end
  end

  defp create_message_record(msg) do
    case Ash.create(
           SmsGateway.Sms.Message,
           %{
             phone_number: msg.phone,
             content: msg.content,
             metadata: %{
               modem_index: msg.index,
               modem_status: msg.status
             }
           },
           action: :create_incoming
         ) do
      {:ok, _message} ->
        Logger.info("Created incoming message from #{msg.phone}")

      {:error, reason} ->
        Logger.error("Failed to create message: #{inspect(reason)}")
    end
  rescue
    e ->
      Logger.error("Error creating message record: #{inspect(e)}")
  end

  # ============================================================================
  # Persistent State
  # ============================================================================

  defp load_last_seen_index do
    Agent.start_link(fn -> get_stored_last_seen_index() end, name: :poller_state)
    Agent.get(:poller_state, & &1)
  rescue
    _ -> get_stored_last_seen_index()
  end

  defp get_stored_last_seen_index do
    case Application.get_env(:sms_gateway, :modem_poller_last_index) do
      nil -> 0
      index -> index
    end
  end

  defp save_last_seen_index(index) do
    Application.put_env(:sms_gateway, :modem_poller_last_index, index)

    if Process.whereis(:poller_state) do
      Agent.update(:poller_state, fn _ -> index end)
    end
  end
end
