defmodule SmsGateway.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false, size: 255
      add :key_hash, :string, null: false, size: 255
      add :key_prefix, :string, null: false, size: 20
      add :is_active, :boolean, default: true, null: false
      add :rate_limit, :integer
      add :metadata, :map, default: %{}
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:api_keys, [:key_hash])
  end
end
