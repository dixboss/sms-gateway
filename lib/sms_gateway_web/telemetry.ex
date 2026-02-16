defmodule SmsGatewayWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("sms_gateway.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("sms_gateway.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("sms_gateway.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("sms_gateway.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("sms_gateway.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # SMS Gateway Metrics
      counter("sms_gateway.sms.sent.count",
        description: "Total number of SMS successfully sent"
      ),
      counter("sms_gateway.sms.failed.count",
        description: "Total number of SMS that failed to send"
      ),
      counter("sms_gateway.sms.delivered.count",
        description: "Total number of SMS confirmed delivered"
      ),
      counter("sms_gateway.sms.received.count",
        description: "Total number of SMS received"
      ),
      last_value("sms_gateway.modem.signal_strength",
        description: "Current modem signal strength (0-100)"
      ),
      counter("sms_gateway.modem.error.count",
        description: "Total modem errors"
      ),
      last_value("sms_gateway.queue.pending",
        description: "Number of pending SMS in queue"
      ),
      last_value("sms_gateway.queue.executing",
        description: "Number of SMS currently being sent"
      ),

      # Oban Metrics
      summary("oban.job.start.system_time",
        unit: {:native, :millisecond},
        tags: [:worker]
      ),
      summary("oban.job.stop.duration",
        unit: {:native, :millisecond},
        tags: [:worker]
      ),
      summary("oban.job.exception.duration",
        unit: {:native, :millisecond},
        tags: [:worker]
      ),
      counter("oban.job.complete.count",
        tags: [:worker, :state]
      )
    ]
  end

  defp periodic_measurements do
    [
      # Periodic measurements for queue status
      {__MODULE__, :measure_queue_status, []}
    ]
  end

  @doc """
  Periodically measure Oban queue status and emit telemetry events.
  """
  def measure_queue_status do
    try do
      case Oban.check_queue(queue: :sms_send) do
        {:ok, stats} ->
          pending = stats.available + stats.scheduled
          executing = stats.executing

          :telemetry.execute(
            [:sms_gateway, :queue, :status],
            %{pending: pending, executing: executing},
            %{queue: :sms_send}
          )

        _ ->
          :ok
      end
    rescue
      _ -> :ok
    end
  end
end
