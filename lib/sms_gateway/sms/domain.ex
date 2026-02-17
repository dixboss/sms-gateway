defmodule SmsGateway.Sms do
  use Ash.Domain,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource(SmsGateway.Sms.ApiKey)
    resource(SmsGateway.Sms.Message)
  end
end
