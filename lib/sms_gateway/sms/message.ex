defmodule SmsGateway.Sms.Message do
  use Ash.Resource,
    domain: SmsGateway.Sms,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("messages")
    repo(SmsGateway.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :direction, :atom do
      allow_nil?(false)
      constraints(one_of: [:outgoing, :incoming])
    end

    attribute :phone_number, :string do
      allow_nil?(false)
      constraints(max_length: 20)
    end

    attribute :content, :string do
      allow_nil?(false)
      constraints(max_length: 160)
    end

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:pending, :queued, :sending, :sent, :delivered, :failed, :received])
      default(:pending)
    end

    attribute :modem_message_id, :string do
      constraints(max_length: 50)
    end

    attribute(:error_message, :string)

    attribute(:sent_at, :utc_datetime)

    attribute(:delivered_at, :utc_datetime)

    attribute(:received_at, :utc_datetime)

    attribute :metadata, :map do
      default(%{})
    end

    timestamps()
  end

  relationships do
    belongs_to :api_key, SmsGateway.Sms.ApiKey do
      allow_nil?(true)
    end
  end

  actions do
    defaults([:create, :read, :update, :destroy])

    read :list do
      pagination(offset?: true)
    end

    read :by_status do
      argument :status, :atom do
        constraints(one_of: [:pending, :queued, :sending, :sent, :delivered, :failed, :received])
      end

      filter(expr(status == ^arg(:status)))
    end

    read :incoming do
      description("Get all incoming messages")
      filter(expr(direction == :incoming))
    end

    read :outgoing do
      description("Get all outgoing messages")
      filter(expr(direction == :outgoing))
    end

    create :create_outgoing do
      description("Create an outgoing SMS message")

      argument :phone_number, :string do
        allow_nil?(false)
        constraints(max_length: 20)
      end

      argument :content, :string do
        allow_nil?(false)
        constraints(max_length: 160)
      end

      argument(:api_key_id, :uuid)

      change(fn changeset, _context ->
        phone = Ash.Changeset.get_argument(changeset, :phone_number)
        content = Ash.Changeset.get_argument(changeset, :content)
        api_key_id = Ash.Changeset.get_argument(changeset, :api_key_id)

        changeset
        |> Ash.Changeset.change_attributes(%{
          direction: :outgoing,
          phone_number: phone,
          content: content,
          status: :pending,
          api_key_id: api_key_id
        })
      end)

      after_action(fn _changeset, message, _context ->
        # TODO: Create Oban job to send SMS
        {:ok, message}
      end)
    end

    create :create_incoming do
      description("Create an incoming SMS message")

      argument :phone_number, :string do
        allow_nil?(false)
        constraints(max_length: 20)
      end

      argument :content, :string do
        allow_nil?(false)
        constraints(max_length: 160)
      end

      change(fn changeset, _context ->
        phone = Ash.Changeset.get_argument(changeset, :phone_number)
        content = Ash.Changeset.get_argument(changeset, :content)

        changeset
        |> Ash.Changeset.change_attributes(%{
          direction: :incoming,
          phone_number: phone,
          content: content,
          status: :received,
          received_at: DateTime.utc_now()
        })
      end)
    end

    update :mark_sent do
      description("Mark message as sent")
      require_atomic?(false)

      argument(:modem_message_id, :string)

      change(fn changeset, _context ->
        modem_id = Ash.Changeset.get_argument(changeset, :modem_message_id)

        changeset
        |> Ash.Changeset.change_attributes(%{
          status: :sent,
          sent_at: DateTime.utc_now(),
          modem_message_id: modem_id
        })
      end)
    end

    update :mark_delivered do
      description("Mark message as delivered")

      change(set_attribute(:status, :delivered))
      change(set_attribute(:delivered_at, &DateTime.utc_now/0))
    end

    update :mark_failed do
      description("Mark message as failed")
      require_atomic?(false)

      argument(:error_message, :string)

      change(fn changeset, _context ->
        error = Ash.Changeset.get_argument(changeset, :error_message)

        changeset
        |> Ash.Changeset.change_attributes(%{
          status: :failed,
          error_message: error
        })
      end)
    end
  end
end
