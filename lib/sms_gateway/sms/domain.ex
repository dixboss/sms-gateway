defmodule SmsGateway.Sms do
  use Ash.Domain

  resources do
    resource(SmsGateway.Sms.ApiKey)
    resource(SmsGateway.Sms.Message)
  end
end
