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
  # Every verb in `Catalog::NAMES` needs a branch here; the catalog spec
  # runs `noir help <verb>` for each one, so a missing branch fails there
  # instead of becoming a verb that quietly has no help page.
  def self.run(argv : Array(String))
    case argv.first?
    when nil, "help"  then print_top_level
    when "scan"       then ScanCommand.run(["--help"])
    when "list"       then ListCommand.print_help
    when "cache"      then CacheCommand.print_help
    when "config"     then ConfigCommand.print_help
    when "rules"      then RulesCommand.print_help
    when "completion" then CompletionCommand.print_help
    when "version"    then VersionCommand.print_help
    else
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
        -v, -V, --version Print the noir version and exit; after a verb, use `noir version`
                          (a subcommand's own -v is its own — e.g. `noir rules update -v`)
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
