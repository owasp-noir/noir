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
  # unit specs without triggering the `exit`/`die` side effects.
  record Parsed, action : String?, help : Bool

  def self.parse_argv(argv : Array(String)) : Parsed
    action = nil
    help = false
    argv.each do |a|
      case a
      when "-h", "--help"
        help = true
      else
        action ||= a
      end
    end
    Parsed.new(action: action, help: help)
  end

  def self.run(argv : Array(String))
    parsed = parse_argv(argv)

    if parsed.help || parsed.action.nil?
      print_help
      exit
    end

    case parsed.action
    when "list"   then list_rules
    when "update" then update_rules
    when "path"   then puts rules_path
    else
      Noir::CLI.die("Unknown rules action: #{parsed.action}. Valid: #{ACTIONS.join(", ")}.")
    end
  end

  def self.print_help(io : IO = STDOUT)
    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    io.puts <<-HELP
      #{green.call("USAGE:")}
        noir rules <action>

      #{green.call("ACTIONS:")}
        #{cyan.call("list")}                   Show rule files installed under the rules path
        #{cyan.call("update")}                 Pull the latest rules from the upstream repository
        #{cyan.call("path")}                   Print the configured rules directory

      Default rules path: ~/.config/noir/passive_rules (overridable via NOIR_HOME).

      During scan, rules are activated with `noir scan ... --passive` and
      can be aimed at a custom location with `--passive-scan-path PATH`.
      HELP
  end

  def self.rules_path : String
    File.join(get_home, "passive_rules")
  end

  def self.list_rules(io : IO = STDOUT)
    path = rules_path
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

  def self.update_rules
    logger = NoirLogger.new(false, false, true, false)
    unless PassiveRulesUpdater.initialize_rules(logger)
      logger.warning "Could not initialize passive rules at #{rules_path}."
      return
    end

    if PassiveRulesUpdater.check_for_updates(logger, true)
      logger.success "Passive rules are ready (#{rules_path})."
    else
      # `check_for_updates` returns false either because the fetch
      # failed or because rules are behind and auto-update could not
      # complete cleanly — surface that explicitly so `noir rules
      # update` is never silent.
      logger.warning "Passive rules update did not complete cleanly. See logs above."
    end
  end
end
