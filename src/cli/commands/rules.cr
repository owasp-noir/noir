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

  def self.run(argv : Array(String))
    action = nil
    argv.each do |a|
      case a
      when "-h", "--help"
        print_help
        exit
      else
        action ||= a
      end
    end

    if action.nil?
      print_help
      exit
    end

    case action
    when "list"   then list_rules
    when "update" then update_rules
    when "path"   then puts rules_path
    else
      Noir::CLI.die("Unknown rules action: #{action}. Valid: #{ACTIONS.join(", ")}.")
    end
  end

  def self.print_help
    puts <<-HELP
      USAGE:
        noir rules <action>

      ACTIONS:
        list                 Show rule files installed under the rules path
        update               Pull the latest rules from the upstream repository
        path                 Print the configured rules directory

      Default rules path: ~/.config/noir/passive_rules (overridable via NOIR_HOME).

      During scan, rules are activated with `noir scan ... --passive` and
      can be aimed at a custom location with `--passive-scan-path PATH`.
      HELP
  end

  def self.rules_path : String
    File.join(get_home, "passive_rules")
  end

  def self.list_rules
    path = rules_path
    unless Dir.exists?(path)
      puts "Rules directory does not exist: #{path}"
      puts "Run `noir rules update` to clone the upstream rules repository."
      return
    end

    rule_files = Dir.glob(File.join(path, "**/*.{yml,yaml}"))
    if rule_files.empty?
      puts "No rule files found under #{path}."
      puts "Run `noir rules update` to fetch the latest rules."
      return
    end

    puts "Rules path: #{path}"
    puts "Rule files (#{rule_files.size}):"
    rule_files.sort.each do |file|
      rel = file.sub(path + "/", "")
      puts "  #{rel}"
    end
  end

  def self.update_rules
    logger = NoirLogger.new(false, false, true, false)
    if PassiveRulesUpdater.initialize_rules(logger)
      PassiveRulesUpdater.check_for_updates(logger, true)
    end
  end
end
