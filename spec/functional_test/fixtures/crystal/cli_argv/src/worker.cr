dry_run = ARGV == ["--dry-run"]
interval = ENV["DEMO_INTERVAL"]? || "60"
puts dry_run, interval
