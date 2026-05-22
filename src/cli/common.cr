require "colorize"

module Noir::CLI
  # Known top-level verbs. The router falls back to `scan` when ARGV[0]
  # is not one of these (preserving the `noir -b ./app` v0 usage pattern).
  KNOWN_COMMANDS = [
    "scan",
    "list",
    "cache",
    "config",
    "rules",
    "completion",
    "version",
    "help",
  ]

  def self.die(message : String, code : Int32 = 1) : NoReturn
    STDERR.puts "ERROR: #{message}".colorize(:yellow)
    exit(code)
  end

  def self.color_enabled?(argv : Array(String)) : Bool
    return false if argv.includes?("--no-color")
    return false if ENV["NO_COLOR"]? == "1" || ENV["NO_COLOR"]? == "true"
    true
  end

  def self.colorize_if(s : String, color, argv : Array(String) = ARGV) : String
    color_enabled?(argv) ? s.colorize(color).to_s : s
  end
end
