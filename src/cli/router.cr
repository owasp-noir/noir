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
    elsif likely_mistyped_command?(head)
      # A bare word that is neither a known command nor an existing path is
      # almost certainly a mistyped subcommand. Pre-fix this fell through to
      # scan and surfaced the misleading "Base path does not exist: <word>".
      Noir::CLI.die("Unknown command or non-existent path: '#{head}'.\n" \
                    "Run 'noir help' to see commands, or 'noir scan #{head}' to scan a path.")
    else
      # v0 compat: bare flags or an existing positional path → default to scan.
      ScanCommand.run(argv)
    end
  end

  # True for a first token that looks like a mistyped subcommand: not a flag,
  # not a known command, has no path separator/extension, and doesn't exist on
  # disk. Real scan targets (`./app`, `app.rb`, an existing dir) are excluded
  # so the v0 `noir <path>` shorthand keeps working.
  private def self.likely_mistyped_command?(head : String) : Bool
    return false if head.starts_with?("-")
    return false if KNOWN_COMMANDS.includes?(head)
    return false if head.includes?("/") || head.includes?(".")
    return false if File.exists?(head)
    true
  end

  # Router-consumed global flags. `apply_global_color_flag!` already
  # acted on `--no-color`, and `--no-spinner` only means anything to a
  # scan's loading spinner. Neither is meaningful to the thin
  # subcommands, whose "first positional = action/subject" parsers would
  # otherwise misread a leading `--no-color` as the action itself
  # (`Unknown cache action: --no-color`). They're stripped before those
  # commands parse. `scan` is deliberately excluded: its own OptionParser
  # re-reads both flags to thread color/spinner state through
  # NoirRunner, so scan keeps the full argv.
  GLOBAL_FLAGS = ["--no-color", "--no-spinner"]

  # Pure helper (no exit/die) so the strip rule stays unit-testable.
  def self.strip_global_flags(args : Array(String)) : Array(String)
    args.reject { |arg| GLOBAL_FLAGS.includes?(arg) }
  end

  private def self.route(command : String, args : Array(String))
    case command
    when "scan"       then ScanCommand.run(args)
    when "list"       then ListCommand.run(strip_global_flags(args))
    when "cache"      then CacheCommand.run(strip_global_flags(args))
    when "config"     then ConfigCommand.run(strip_global_flags(args))
    when "rules"      then RulesCommand.run(strip_global_flags(args))
    when "completion" then CompletionCommand.run(strip_global_flags(args))
    when "version"    then VersionCommand.run(strip_global_flags(args))
    when "help"       then HelpCommand.run(strip_global_flags(args))
    else
      # KNOWN_COMMANDS guards this branch — should never be reached.
      Noir::CLI.die("Unknown command: #{command}")
    end
  end
end
