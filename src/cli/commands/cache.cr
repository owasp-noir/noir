require "colorize"
require "../common"
require "../../llm/cache"

# `noir cache <info|clear|purge>`
#
# Managed resource: the on-disk LLM response cache.
module Noir::CLI::CacheCommand
  ACTIONS = %w[info clear purge]

  def self.run(argv : Array(String))
    action = nil
    rest = [] of String
    argv.each do |a|
      case a
      when "-h", "--help"
        print_help
        exit
      else
        if action.nil?
          action = a
        else
          rest << a
        end
      end
    end

    if action.nil?
      print_help
      exit
    end

    case action
    when "info"  then print_info
    when "clear" then clear
    when "purge" then purge(rest)
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
        #{cyan.call("info")}                   Show cache location, entry count, size, and oldest/newest entry
        #{cyan.call("clear")}                  Remove every cached AI response
        #{cyan.call("purge")} #{cyan.call("<days>")}           Remove cached entries older than N days

      #{green.call("SCAN-TIME FLAGS")} (control cache per scan run):
        --cache-disable        Disable cache reads/writes for that scan
        --cache-clear          Clear the cache before that scan runs

      Environment:
        NOIR_CACHE_DISABLE=1   Disables the cache regardless of CLI flags
      HELP
  end

  def self.print_info
    stats = LLM::Cache.stats
    puts "Cache directory: #{LLM::Cache.cache_dir}"
    puts "Entries:         #{stats.entries}"
    puts "Total size:      #{format_bytes(stats.bytes)}"
    if stats.entries > 0
      if oldest = stats.oldest
        puts "Oldest entry:    #{oldest.to_local} (#{format_age(oldest)} ago)"
      end
      if newest = stats.newest
        puts "Newest entry:    #{newest.to_local} (#{format_age(newest)} ago)"
      end
    end
    puts "Enabled:         #{LLM::Cache.enabled?}"
    if LLM::Cache.disabled_by_env?
      puts "  (disabled via NOIR_CACHE_DISABLE)"
    end
    puts ""
    puts "To disable for a single scan: --cache-disable"
    puts "To disable persistently:      export NOIR_CACHE_DISABLE=1"
  end

  def self.clear
    outcome = LLM::Cache.clear
    msg = "Removed #{outcome.deleted} cache entr#{outcome.deleted == 1 ? "y" : "ies"} from #{LLM::Cache.cache_dir}."
    msg += " (#{outcome.failed} failed)" if outcome.failed > 0
    puts msg
  end

  def self.purge(rest : Array(String))
    if rest.empty?
      Noir::CLI.die("Missing <days> argument. Usage: noir cache purge <days>")
    end

    days = rest.first.to_i?
    if days.nil? || days < 1
      Noir::CLI.die("Invalid <days> '#{rest.first}'. Must be a positive integer.")
    end

    outcome = LLM::Cache.purge_older_than(days)
    msg = "Purged #{outcome.deleted} cache entr#{outcome.deleted == 1 ? "y" : "ies"} older than #{days} day#{days == 1 ? "" : "s"} from #{LLM::Cache.cache_dir}."
    msg += " (#{outcome.failed} failed)" if outcome.failed > 0
    puts msg
  end

  private def self.format_bytes(bytes : Int64) : String
    return "#{bytes} B" if bytes < 1024
    kb = bytes / 1024.0
    return "#{kb.round(1)} KB" if kb < 1024
    mb = kb / 1024.0
    return "#{mb.round(1)} MB" if mb < 1024
    "#{(mb / 1024.0).round(2)} GB"
  end

  private def self.format_age(t : Time) : String
    seconds = (Time.utc - t.to_utc).total_seconds.to_i64
    return "#{seconds}s" if seconds < 60
    minutes = seconds // 60
    return "#{minutes}m" if minutes < 60
    hours = minutes // 60
    return "#{hours}h" if hours < 24
    days = hours // 24
    "#{days}d"
  end
end
