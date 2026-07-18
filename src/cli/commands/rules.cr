require "colorize"
require "file"
require "../common"
require "../../models/logger"
require "../../utils/home"
require "../../utils/passive_rules_updater"

# `noir rules <list|update|path>`
#
# Managed resource: the passive-scan rules repository (cloned from
# owasp-noir/noir-passive-rules into ~/.config/noir/passive_rules/).
module Noir::CLI::RulesCommand
  ACTIONS = %w[list update path]

  # Parsed argv. Pulled out of `run` so the parser can be exercised in
  # unit specs without triggering the `exit`/`die` side effects. `error`
  # is recorded (rather than raised) when argv is malformed so `run` can
  # turn it into a clean `Noir::CLI.die` line.
  record Parsed,
    action : String?,
    help : Bool,
    debug : Bool,
    verbose : Bool,
    error : String?

  def self.parse_argv(argv : Array(String)) : Parsed
    action = nil
    help = false
    debug = false
    verbose = false
    error = nil
    extra = [] of String

    argv.each do |a|
      case a
      when "-h", "--help"
        help = true
      when "--debug"
        debug = true
      when "-v", "--verbose"
        verbose = true
      when "--no-color"
        # Global flag — the router already applied it via
        # `Noir::CLI.apply_global_color_flag!`. Accept it here so it isn't
        # rejected as an unknown option.
      else
        if a.starts_with?("-")
          error ||= "Unknown option: #{a}. Run `noir rules --help`."
        elsif action.nil?
          action = a
        else
          extra << a
        end
      end
    end

    # A second positional (a typo'd or copy-pasted extra subcommand) used to
    # be silently dropped — `noir rules list update` quietly ran only `list`.
    # Surface it instead of guessing which one the user meant.
    if error.nil? && !extra.empty?
      plural = extra.size > 1 ? "s" : ""
      error = "Unexpected argument#{plural}: #{extra.join(", ")}. `noir rules` takes a single action."
    end

    Parsed.new(action: action, help: help, debug: debug, verbose: verbose, error: error)
  end

  def self.run(argv : Array(String))
    parsed = parse_argv(argv)

    if parsed.help
      print_help
      exit
    end

    if err = parsed.error
      Noir::CLI.die(err)
    end

    if parsed.action.nil?
      print_help
      exit
    end

    case parsed.action
    when "list"   then list_rules
    when "update" then update_rules(parsed.debug, parsed.verbose)
    when "path"   then puts effective_rules_path
    else
      Noir::CLI.die("Unknown rules action: #{parsed.action}. Valid: #{ACTIONS.join(", ")}.")
    end
  rescue ex : File::Error
    # `Dir.exists?` / `Dir.glob` raise (rather than return false) when the
    # rules path or an ancestor can't be stat'd — a permission-denied parent,
    # a stale mount. Fail like every other subcommand: one clean line, not a
    # raw Crystal stack trace.
    Noir::CLI.die("Cannot access the rules directory: #{ex.message}")
  end

  def self.print_help(io : IO = STDOUT)
    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    io.puts <<-HELP
      #{green.call("USAGE:")}
        noir rules <action> [options]

      #{green.call("ACTIONS:")}
        #{cyan.call("list")}                   Show rule files installed under the rules path
        #{cyan.call("update")}                 Pull the latest rules from the upstream repository
        #{cyan.call("path")}                   Print the configured rules directory

      #{green.call("OPTIONS:")}
        #{cyan.call("-v")}, #{cyan.call("--verbose")}          Show verbose progress (update)
        #{cyan.call("--debug")}                Show debug diagnostics, e.g. why an update failed
        #{cyan.call("-h")}, #{cyan.call("--help")}             Show this help

      Default rules path: ~/.config/noir/passive_rules (overridable via NOIR_HOME).

      During scan, rules are activated with `noir scan ... -P` (--passive-scan)
      and can be aimed at a custom location with `--passive-scan-path PATH`.
      HELP
  end

  # The writable, user-managed rules directory: where `noir rules update`
  # clones/pulls. Kept distinct from `effective_rules_path` (which may resolve
  # to the read-only image-baked bundle) so update always targets a path it
  # can actually write to.
  def self.rules_path : String
    PassiveRulesUpdater.user_rules_path
  end

  # What `noir scan -P` actually reads rules from: the user-managed path when
  # populated, otherwise the image-baked bundle at /opt/noir/passive_rules.
  # `list`/`path` report this so they never claim "no rules" on a Docker
  # install where passive scanning is fully working off the bundled ruleset.
  def self.effective_rules_path : String
    PassiveRulesUpdater.effective_rules_path
  end

  def self.list_rules(io : IO = STDOUT)
    path = effective_rules_path
    unless Dir.exists?(path)
      io.puts "Rules directory does not exist: #{path}"
      io.puts "Run `noir rules update` to clone the upstream rules repository."
      return
    end

    rule_files = Dir.glob(File.join(path, "**/*.{yml,yaml}"))
    if rule_files.empty?
      io.puts "No rule files found under #{path}."
      io.puts "Run `noir rules update` to fetch the latest rules."
      return
    end

    io.puts "Rules path: #{path}"
    io.puts "Rule files (#{rule_files.size}):"
    rule_files.sort.each do |file|
      rel = file.sub(path + "/", "")
      io.puts "  #{rel}"
    end
  end

  def self.update_rules(debug : Bool = false, verbose : Bool = false)
    # Honour the global --no-color / NO_COLOR state the router already
    # resolved (Colorize.enabled?) instead of forcing color on, and let
    # --debug/-v surface why an update didn't complete.
    logger = NoirLogger.new(debug, verbose, Colorize.enabled?, false)

    unless PassiveRulesUpdater.initialize_rules(logger)
      logger.warning "Could not initialize passive rules at #{rules_path}."
      # A failed init means `-P` scans would silently run with no rules;
      # exit non-zero so `noir rules update && noir scan . -P` is a usable
      # precondition check in CI/scripts.
      exit(1)
    end

    if PassiveRulesUpdater.check_for_updates(logger, true)
      logger.success "Passive rules are ready (#{effective_rules_path})."
    else
      # The specific reason (bad remote, non-git dir, fetch failure) is logged
      # at debug level, so point the user at `--debug` rather than "logs above"
      # that a default run never actually printed.
      if debug || verbose
        logger.warning "Passive rules update did not complete cleanly. See the diagnostics above."
      else
        logger.warning "Passive rules update did not complete cleanly. Re-run `noir rules update --debug` for details."
      end
      exit(1)
    end
  end
end
