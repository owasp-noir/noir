require "colorize"
require "../common"
require "../catalog"
require "../../banner"

# `noir help [command]`
#
# `noir help` (no args) prints the top-level overview. This is also
# what `noir` with no arguments and `noir -h` resolve to.
# `noir help scan` (etc.) defers to the matching command's help.
module Noir::CLI::HelpCommand
  # Commands recognised by `noir help <cmd>`. The same verbs the router
  # dispatches — `route_for` below maps each to its help printer, and a
  # catalog entry with no branch there is a compile error rather than a
  # verb that quietly has no help page.
  KNOWN_HELP_TARGETS = Noir::CLI::Catalog::NAMES

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
    Noir::Banner.print(banner_io)

    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    io.puts <<-HELP
      #{green.call("USAGE:")}
        noir <command> [arguments] [flags]
        noir [flags]                       # v0-compatible: routes to `noir scan`

      #{green.call("COMMANDS:")}
      #{command_lines(cyan)}

      #{green.call("GLOBAL FLAGS:")}
        --no-color        Strip ANSI color from every command's output (NO_COLOR env also works)
        --no-spinner      Disable loading spinner animations while keeping normal logs
        -v, -V, --version Print the noir version and exit (alias for `noir version`)
        -h, --help        Show this overview, or, after a verb, that command's help

      Run `noir help <command>` (or `noir <command> -h`) for command-specific flags.
      HELP
  end

  # The COMMANDS block, laid out from the catalog. The description column is
  # aligned on the widest `verb args` pair, so a new subcommand doesn't need
  # the whole block re-padded by hand — nor does it need to be added here at
  # all.
  private def self.command_lines(cyan : Proc(String, String)) : String
    commands = Noir::CLI::Catalog::COMMANDS
    width = commands.max_of { |command| "#{command.name} #{command.usage_args}".size }

    commands.map do |command|
      # Padding is measured on the uncolored text: the ANSI escapes around
      # the verb are zero-width on screen but count toward String#size.
      padding = " " * (width - "#{command.name} #{command.usage_args}".size)
      "  #{cyan.call(command.name)} #{command.usage_args}#{padding}  #{command.summary}"
    end.join("\n")
  end
end
