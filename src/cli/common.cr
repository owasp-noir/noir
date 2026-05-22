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

  # Disable Crystal's Colorize globally when the user asks for plain
  # output via `--no-color` or the `NO_COLOR` env var. Applied at the
  # router layer so every subcommand (list / cache / config / rules /
  # completion / version / help / scan) picks it up — scan's own parser
  # still also sees `--no-color` and threads it through NoirRunner for
  # the in-scan logger.
  def self.apply_global_color_flag!(argv : Array(String))
    return Colorize.enabled = false if no_color_env?
    return Colorize.enabled = false if argv.includes?("--no-color")
    nil
  end

  def self.no_color_env? : Bool
    value = ENV["NO_COLOR"]?
    return false if value.nil? || value.empty?
    value != "0"
  end

  def self.die(message : String, code : Int32 = 1) : NoReturn
    STDERR.puts "ERROR: #{message}".colorize(:yellow)
    exit(code)
  end

  # Shared accent helpers so every `-h` page styles its section labels
  # and inline command names the same way — green for headers (USAGE,
  # SUBJECTS, ACTIONS, OPTIONS, …), cyan for the named items inside.
  def self.section(label : String) : String
    label.colorize(:green).to_s
  end

  def self.name(label : String) : String
    label.colorize(:cyan).to_s
  end
end
