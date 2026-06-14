# Shared base class. Route files inherit from this, NOT from Grape::API
# directly, so the analyzer must follow the inheritance chain to recognise
# them as Grape APIs.
module MyAPI
  class Base < Grape::API
  end
end
