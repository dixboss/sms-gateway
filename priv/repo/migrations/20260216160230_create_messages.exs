defmodule SmsGateway.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :direction, :string, null: false, size: 10
      add :phone_number, :string, null: false, size: 20
      add :content, :text, null: false
      add :status, :string, null: false, size: 20
      add :modem_message_id, :string, size: 50
      add :api_key_id, references(:api_keys, type: :uuid, on_delete: :nilify_all)
      add :error_message, :text
      add :sent_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :received_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    # Add check constraints
    create constraint(:messages, :direction_must_be_valid,
             check: "direction IN ('outgoing', 'incoming')"
           )

    create constraint(:messages, :status_must_be_valid,
             check:
               "status IN ('pending', 'queued', 'sending', 'sent', 'delivered', 'failed', 'received')"
           )

    # Add indexes for performance
    create index(:messages, [:status])
    create index(:messages, [:direction])
    create index(:messages, [:api_key_id])
    create index(:messages, [:inserted_at])
    create index(:messages, [:phone_number])
  end
end
