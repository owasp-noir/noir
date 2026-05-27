require "colorize"
require "../common"
require "../../banner"

# `noir help [command]`
#
# `noir help` (no args) prints the top-level overview. This is also
# what `noir` with no arguments and `noir -h` resolve to.
# `noir help scan` (etc.) defers to the matching command's help.
module Noir::CLI::HelpCommand
  # Commands recognised by `noir help <cmd>`. Kept here (rather than
  # via KNOWN_COMMANDS) because each entry maps to a specific help
  # printer, and adding a new subcommand needs a deliberate edit to
  # both routes.
  KNOWN_HELP_TARGETS = %w[scan list cache config rules completion version help]

  # Returns a routing symbol so the spec layer can verify dispatch
  # without invoking the downstream command's help printer (which in
  # `scan`'s case re-runs the whole OptionParser).
  enum Route
    TopLevel
    Scan
    List
    Cache
    Config
    Rules
    Completion
    Version
    Help
    Unknown
  end

  def self.route_for(argv : Array(String)) : Route
    return Route::TopLevel if argv.empty?

    case argv.first
    when "scan"       then Route::Scan
    when "list"       then Route::List
    when "cache"      then Route::Cache
    when "config"     then Route::Config
    when "rules"      then Route::Rules
    when "completion" then Route::Completion
    when "version"    then Route::Version
    when "help"       then Route::Help
    else
      Route::Unknown
    end
  end

  def self.run(argv : Array(String))
    case route_for(argv)
    in Route::TopLevel   then print_top_level
    in Route::Scan       then ScanCommand.run(["--help"])
    in Route::List       then ListCommand.print_help
    in Route::Cache      then CacheCommand.print_help
    in Route::Config     then ConfigCommand.print_help
    in Route::Rules      then RulesCommand.print_help
    in Route::Completion then CompletionCommand.print_help
    in Route::Version    then VersionCommand.print_help
    in Route::Help       then print_top_level
    in Route::Unknown
      Noir::CLI.die("Unknown command: #{argv.first}\nRun `noir help` to see available commands.")
    end
  end

  def self.print_top_level(io : IO = STDOUT, banner_io : IO = STDERR)
    banner(banner_io)

    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    io.puts <<-HELP
      #{green.call("USAGE:")}
        noir <command> [arguments] [flags]
        noir [flags]                       # v0-compatible: routes to `noir scan`

      #{green.call("COMMANDS:")}
        #{cyan.call("scan")} [PATHS...]                   Discover endpoints in one or more codebases
        #{cyan.call("list")} techs | taggers | formats    Enumerate built-in catalogs
        #{cyan.call("cache")} info | clear | purge        Manage the on-disk LLM response cache
        #{cyan.call("config")} show | edit | init | path  Manage the user-level YAML configuration
        #{cyan.call("rules")} list | update | path        Manage the passive-scan rules repository
        #{cyan.call("completion")} <shell>                Generate shell completion (zsh, bash, fish, elvish)
        #{cyan.call("version")} [--verbose]               Print version (or full build details)
        #{cyan.call("help")} [command]                    Show this overview or a command's help

      #{green.call("GLOBAL FLAGS:")}
        --no-color     Strip ANSI color from every command's output (NO_COLOR env also works)
        --no-spinner   Disable loading spinner animations while keeping normal logs
        -v, --version  Print the noir version and exit (alias for `noir version`)
        -h, --help     Show this overview, or, after a verb, that command's help

      Run `noir help <command>` (or `noir <command> -h`) for command-specific flags.
      HELP
  end
end
