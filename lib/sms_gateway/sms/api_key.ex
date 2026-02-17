defmodule SmsGateway.Sms.ApiKey do
  use Ash.Resource,
    domain: SmsGateway.Sms,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  admin do
    table_columns([:name, :key_prefix, :is_active, :rate_limit, :last_used_at, :inserted_at])

    form do
      field :name
      field :rate_limit
      # key_hash and key_prefix are generated automatically by :create action
    end
  end

  postgres do
    table("api_keys")
    repo(SmsGateway.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      constraints(max_length: 255)
    end

    attribute :key_hash, :string do
      allow_nil?(false)
      constraints(max_length: 255)
    end

    attribute :key_prefix, :string do
      allow_nil?(false)
      constraints(max_length: 20)
    end

    attribute :is_active, :boolean do
      allow_nil?(false)
      default(true)
    end

    attribute(:rate_limit, :integer)

    attribute :metadata, :map do
      default(%{})
    end

    attribute(:last_used_at, :utc_datetime)

    timestamps()
  end

  actions do
    defaults([:read, :update, :destroy])

    read :list do
      filter(expr(is_active == true))
    end

    read :by_prefix do
      argument :prefix, :string do
        allow_nil?(false)
      end

      filter(expr(key_prefix == ^arg(:prefix) and is_active == true))
      get?(true)
    end

    # Custom create action that generates key_hash and key_prefix automatically
    create :create do
      accept([:name, :rate_limit])

      change(fn changeset, _context ->
        name = Ash.Changeset.get_attribute(changeset, :name)
        rate_limit = Ash.Changeset.get_attribute(changeset, :rate_limit)

        # Generate a new secret key (32 bytes random)
        secret_key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
        # Prefix: "sk_live_" (8 chars) + 11 chars = 19 chars total (under 20 limit)
        prefix = "sk_live_" <> String.slice(secret_key, 0..10)
        key_hash = Bcrypt.hash_pwd_salt(secret_key)

        changeset
        |> Ash.Changeset.change_attributes(%{
          name: name,
          key_hash: key_hash,
          key_prefix: prefix,
          rate_limit: rate_limit
        })
      end)
    end

    update :deactivate do
      change(set_attribute(:is_active, false))
    end

    update :touch_last_used do
      change(set_attribute(:last_used_at, &DateTime.utc_now/0))
    end
  end
end
