action = ARGV.first? || "help"
db = ENV.fetch("DEMO_DB_URL")
puts action, db
