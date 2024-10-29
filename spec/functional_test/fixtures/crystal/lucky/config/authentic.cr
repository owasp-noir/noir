require "./server"

Authentic.configure do |settings|
  settings.secret_key = Lucky::Server.settings.secret_key_base

  unless LuckyEnv.production?
    # This value can be between 4 and 31
    fastest_encryption_possible = 4
    settings.encryption_cost = fastest_encryption_possible
  end
end
