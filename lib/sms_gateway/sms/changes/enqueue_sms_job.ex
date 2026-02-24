defmodule SmsGateway.Sms.Changes.EnqueueSmsJob do
  @moduledoc """
  Change module that enqueues an Oban job to send the SMS after the message is created.

  This is more reliable than using after_transaction hooks, as it executes
  within the same database transaction and guarantees the job is created.
  """
  use Ash.Resource.Change
  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    # Use after_action to execute after the record is saved but before transaction commits
    Ash.Changeset.after_action(changeset, fn _changeset, message ->
      case enqueue_job(message) do
        {:ok, _job} ->
          Logger.info("Enqueued SMS job for message #{message.id}")
          {:ok, message}

        {:error, reason} ->
          Logger.error("Failed to enqueue SMS job: #{inspect(reason)}")
          # Return error to rollback the transaction
          {:error, "Failed to enqueue SMS job: #{inspect(reason)}"}
      end
    end)
  end

  defp enqueue_job(message) do
    # Use SendSms worker with Req + CurlReq (100% Elixir with curl debugging)
    Oban.insert(SmsGateway.Workers.SendSms.new(%{message_id: message.id}))
  end
end
