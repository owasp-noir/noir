require "colorize"
require "../common"
require "../../banner"

# `noir help [command]`
#
# `noir help` (no args) prints the top-level overview — the canonical
# entry point when a user types `noir` with no arguments.
# `noir help scan` (etc.) defers to the matching command's help.
module Noir::CLI::HelpCommand
  def self.run(argv : Array(String))
    if argv.empty?
      print_top_level
      return
    end

    case argv.first
    when "scan"       then ScanCommand.run(["--help"])
    when "list"       then ListCommand.print_help
    when "cache"      then CacheCommand.print_help
    when "config"     then ConfigCommand.print_help
    when "rules"      then RulesCommand.print_help
    when "completion" then CompletionCommand.print_help
    when "version"    then VersionCommand.print_help
    when "help"       then print_top_level
    else
      Noir::CLI.die("Unknown command: #{argv.first}\nRun `noir help` to see available commands.")
    end
  end

  def self.print_top_level
    banner()

    cyan = ->(s : String) { s.colorize(:cyan).to_s }
    green = ->(s : String) { s.colorize(:green).to_s }

    puts <<-HELP
      #{green.call("USAGE:")}
        noir <command> [arguments] [flags]
        noir [flags]                       # v0-compatible: routes to `noir scan`

      #{green.call("COMMANDS:")}
        #{cyan.call("scan")} [PATHS...]                Discover endpoints in one or more codebases
        #{cyan.call("list")} techs | taggers | formats Enumerate built-in catalogs
        #{cyan.call("cache")} info | clear             Manage the on-disk LLM response cache
        #{cyan.call("config")} show | init | path      Manage the user-level YAML configuration
        #{cyan.call("rules")} list | update | path     Manage the passive-scan rules repository
        #{cyan.call("completion")} <zsh|bash|fish>     Generate shell completion script
        #{cyan.call("version")} [--verbose]            Print version (or full build details)
        #{cyan.call("help")} [command]                 Show this overview or a command's help

      #{green.call("GLOBAL FLAGS:")}
        --no-color    Strip ANSI color from every command's output (NO_COLOR env also works)
        -h, --help    Show this overview, or — after a verb — that command's help

      Run `noir help <command>` (or `noir <command> -h`) for command-specific flags.
      HELP
  end
end
