require "./common"
require "./legacy"
require "./commands/scan"
require "./commands/list"
require "./commands/cache"
require "./commands/config"
require "./commands/rules"
require "./commands/completion"
require "./commands/version"
require "./commands/help"

# Top-level subcommand router.
#
#   noir scan ./app          → ScanCommand
#   noir list techs          → ListCommand
#   noir cache info          → CacheCommand
#   noir config show         → ConfigCommand
#   noir rules update        → RulesCommand
#   noir completion zsh      → CompletionCommand
#   noir version             → VersionCommand
#   noir help                → HelpCommand
#
# Anything else (including the v0 `noir -b ./app` pattern) routes to
# `scan` — the default — preserving every CI script, GitHub Action,
# Dockerfile entrypoint, and shell alias from v0.x.
module Noir::CLI::Router
  def self.dispatch(argv : Array(String) = ARGV)
    Noir::CLI.apply_global_color_flag!(argv)
    argv = Legacy.rewrite(argv)

    if argv.empty?
      HelpCommand.run([] of String)
      return
    end

    head = argv.first

    # `noir -h` / `noir --help` with no other args show the top-level
    # subcommand overview, not scan's full flag dump. (Per-command help
    # is reachable via `noir scan -h`, `noir list -h`, etc.)
    if argv.size == 1 && (head == "-h" || head == "--help")
      HelpCommand.run([] of String)
      return
    end

    if !head.starts_with?("-") && KNOWN_COMMANDS.includes?(head)
      rest = argv[1..]
      route(head, rest)
    else
      # v0 compat: bare flags or unknown positional → default to scan.
      ScanCommand.run(argv)
    end
  end

  private def self.route(command : String, args : Array(String))
    case command
    when "scan"       then ScanCommand.run(args)
    when "list"       then ListCommand.run(args)
    when "cache"      then CacheCommand.run(args)
    when "config"     then ConfigCommand.run(args)
    when "rules"      then RulesCommand.run(args)
    when "completion" then CompletionCommand.run(args)
    when "version"    then VersionCommand.run(args)
    when "help"       then HelpCommand.run(args)
    else
      # KNOWN_COMMANDS guards this branch — should never be reached.
      Noir::CLI.die("Unknown command: #{command}")
    end
  end
end
