require "colorize"
require "../common"
require "../../llm/cache"

# `noir cache <info|clear>`
#
# Managed resource: the on-disk LLM response cache.
module Noir::CLI::CacheCommand
  ACTIONS = %w[info clear]

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
    when "info"  then print_info
    when "clear" then clear
    else
      Noir::CLI.die("Unknown cache action: #{action}. Valid: #{ACTIONS.join(", ")}.")
    end
  end

  def self.print_help
    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    puts <<-HELP
      #{green.call("USAGE:")}
        noir cache <action>

      #{green.call("ACTIONS:")}
        #{cyan.call("info")}                   Show cache location, entry count, and total size
        #{cyan.call("clear")}                  Remove every cached AI response

      #{green.call("LEGACY ALIASES")} (still work on `noir scan`):
        --cache-disable        → disables cache for that scan run
        --cache-clear          → clears the cache before that scan run
      HELP
  end

  def self.print_info
    stats = LLM::Cache.stats
    puts "Cache directory: #{LLM::Cache.cache_dir}"
    puts "Entries:         #{stats["entries"]}"
    puts "Total size:      #{format_bytes(stats["bytes"])}"
    puts "Enabled:         #{LLM::Cache.enabled?}"
    if LLM::Cache.disabled_by_env?
      puts "  (disabled via NOIR_CACHE_DISABLE)"
    end
  end

  def self.clear
    count = LLM::Cache.clear
    puts "Removed #{count} cache entr#{count == 1 ? "y" : "ies"} from #{LLM::Cache.cache_dir}."
  end

  private def self.format_bytes(bytes : Int64) : String
    return "#{bytes} B" if bytes < 1024
    kb = bytes / 1024.0
    return "#{kb.round(1)} KB" if kb < 1024
    mb = kb / 1024.0
    return "#{mb.round(1)} MB" if mb < 1024
    "#{(mb / 1024.0).round(2)} GB"
  end
end
