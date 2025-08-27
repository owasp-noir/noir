require "marten"

Marten.configure do |config|
  config.secret_key = "insecure-key-for-dev"
  config.debug = true
end

require "./routes"

Marten.run
