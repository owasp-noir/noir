require "colorize"
require "../common"
require "../../llm/cache"

# `noir cache <info|clear|purge>`
#
# Managed resource: the on-disk LLM response cache.
module Noir::CLI::CacheCommand
  ACTIONS = %w[info clear purge]

  # Parsed argv. Extracted from `run` so the parser itself stays
  # unit-testable — `run` still owns the `exit`/`die` side effects.
  record Parsed, action : String?, rest : Array(String), help : Bool

  def self.parse_argv(argv : Array(String)) : Parsed
    action = nil
    rest = [] of String
    help = false
    argv.each do |a|
      case a
      when "-h", "--help"
        help = true
      else
        if action.nil?
          action = a
        else
          rest << a
        end
      end
    end
    Parsed.new(action: action, rest: rest, help: help)
  end

  # Upper bound on `noir cache purge <days>`. 100 years is well past
  # any realistic cache retention horizon; the actual reason for the
  # cap is Crystal's `Time.utc - <days>.days` arithmetic, which
  # raises `ArgumentError: Invalid time: seconds out of range` for
  # values that push the resulting Time past the supported range.
  # 100 years stays comfortably inside the Time bounds.
  MAX_PURGE_DAYS = 36_500

  # Returns `days` when `arg` is a positive integer within the
  # representable Time range, `nil` otherwise. Pulled out of `purge`
  # so the validation rule can be exercised without going through
  # the `die` exit path.
  def self.parse_days(arg : String?) : Int32?
    return if arg.nil?
    days = arg.to_i?
    return if days.nil? || days < 1 || days > MAX_PURGE_DAYS
    days
  end

  def self.run(argv : Array(String))
    parsed = parse_argv(argv)

    if parsed.help || parsed.action.nil?
      print_help
      exit
    end

    case parsed.action
    when "info"  then print_info
    when "clear" then clear
    when "purge" then purge(parsed.rest)
    else
      Noir::CLI.die("Unknown cache action: #{parsed.action}. Valid: #{ACTIONS.join(", ")}.")
    end
  end

  def self.print_help(io : IO = STDOUT)
    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    io.puts <<-HELP
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

  def self.print_info(io : IO = STDOUT)
    stats = LLM::Cache.stats
    io.puts "Cache directory: #{LLM::Cache.cache_dir}"
    io.puts "Entries:         #{stats.entries}"
    io.puts "Total size:      #{format_bytes(stats.bytes)}"
    if stats.entries > 0
      if oldest = stats.oldest
        io.puts "Oldest entry:    #{oldest.to_local} (#{format_age(oldest)} ago)"
      end
      if newest = stats.newest
        io.puts "Newest entry:    #{newest.to_local} (#{format_age(newest)} ago)"
      end
    end
    io.puts "Enabled:         #{LLM::Cache.enabled?}"
    if LLM::Cache.disabled_by_env?
      io.puts "  (disabled via NOIR_CACHE_DISABLE)"
    end
    io.puts ""
    io.puts "To disable for a single scan: --cache-disable"
    io.puts "To disable persistently:      export NOIR_CACHE_DISABLE=1"
  end

  def self.clear(io : IO = STDOUT)
    outcome = LLM::Cache.clear
    msg = "Removed #{outcome.deleted} cache entr#{outcome.deleted == 1 ? "y" : "ies"} from #{LLM::Cache.cache_dir}."
    msg += " (#{outcome.failed} failed)" if outcome.failed > 0
    io.puts msg
  end

  def self.purge(rest : Array(String), io : IO = STDOUT)
    if rest.empty?
      Noir::CLI.die("Missing <days> argument. Usage: noir cache purge <days>")
    end

    days = parse_days(rest.first)
    if days.nil?
      Noir::CLI.die("Invalid <days> '#{rest.first}'. Must be a positive integer between 1 and #{MAX_PURGE_DAYS}.")
    end

    outcome = LLM::Cache.purge_older_than(days)
    msg = "Purged #{outcome.deleted} cache entr#{outcome.deleted == 1 ? "y" : "ies"} older than #{days} day#{days == 1 ? "" : "s"} from #{LLM::Cache.cache_dir}."
    msg += " (#{outcome.failed} failed)" if outcome.failed > 0
    io.puts msg
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
