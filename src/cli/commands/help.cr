require "colorize"
require "../common"

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
    cyan = ->(s : String) { s.colorize(:cyan).to_s }
    green = ->(s : String) { s.colorize(:green).to_s }
    yellow = ->(s : String) { s.colorize(:yellow).to_s }
    dim = ->(s : String) { s.colorize(:dark_gray).to_s }

    puts <<-HELP
      #{green.call("Noir")} — hunt every endpoint in your code, expose shadow APIs,
                     map the attack surface.

      #{green.call("USAGE:")}
        noir <command> [arguments] [flags]
        noir [flags]               #{dim.call("# v0-compatible: routes to `noir scan`")}

      #{green.call("CORE COMMAND:")}
        #{cyan.call("scan")} [PATHS...]            Discover endpoints in one or more codebases.
                                  Use positional paths or repeated `-b PATH`.

      #{green.call("CATALOG (read-only enumeration):")}
        #{cyan.call("list techs")}                 Supported languages, frameworks, and analyzers
        #{cyan.call("list taggers")}               Built-in and framework-specific taggers
        #{cyan.call("list formats")}               Supported output formats

      #{green.call("MANAGED RESOURCES:")}
        #{cyan.call("rules")}  list | update | path     Passive-scan rules repository
        #{cyan.call("cache")}  info | clear             On-disk LLM response cache
        #{cyan.call("config")} show | init | path       User-level YAML configuration

      #{green.call("UTILITIES:")}
        #{cyan.call("completion")} <shell>          Generate shell completion (zsh|bash|fish)
        #{cyan.call("version")} [--verbose]         Print version (or build details with --verbose)
        #{cyan.call("help")} [command]              Show this overview or a specific command's help

      #{green.call("EXAMPLES:")}
        #{yellow.call("# v1 idiomatic")}
        noir scan ./app
        noir scan ./api ./worker --passive
        noir scan ./app --ai-context --include path,techs,callee

        #{yellow.call("# v0 still works")}
        noir -b ./app
        noir -b ./api -b ./worker -P -f json -o out.json

      Run `noir help <command>` for the flag surface of any command.
      HELP
  end
end
