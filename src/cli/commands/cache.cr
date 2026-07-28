require "colorize"
require "file"
require "../common"
require "../../llm/cache"

# `noir cache <info|clear|purge>`
#
# Managed resource: the on-disk LLM response cache.
module Noir::CLI::CacheCommand
  ACTIONS = %w[info clear purge]

  # Positionals each action accepts after the action word. `purge` takes
  # `<days>`; the rest take none. Used to reject surplus argv rather than
  # dropping it, which matters most for `clear`: an unrecognized flag
  # used to sail straight through to a real, irreversible wipe.
  ACTION_ARITY = {"info" => 0, "clear" => 0, "purge" => 1}

  # Parsed argv. Extracted from `run` so the parser itself stays
  # unit-testable — `run` still owns the `exit`/`die` side effects.
  # `error` is recorded rather than raised so `run` can turn it into a
  # clean `Noir::CLI.die` line.
  record Parsed, action : String?, rest : Array(String), help : Bool, error : String?

  def self.parse_argv(argv : Array(String)) : Parsed
    action = nil
    rest = [] of String
    help = false
    error = nil

    argv.each do |a|
      case a
      when "-h", "--help"
        help = true
      when "--no-color", "--no-spinner"
        # Global flags — the router consumes both before dispatching here.
        # Accepted (not rejected as unknown) so a direct `run` call and a
        # future router change both behave.
      else
        if flag?(a)
          # Previously an unknown flag was taken as a positional and then
          # ignored, so `noir cache clear --dry-run` cleared the cache for
          # real while reading like a no-op rehearsal.
          error ||= "Unknown option: #{a}. Run `noir cache --help`."
        elsif action.nil?
          action = a
        else
          rest << a
        end
      end
    end

    # Surplus positionals were silently dropped too: `noir cache info
    # clear` quietly ran only `info`, `noir cache purge 3 999` ignored the
    # 999. Surface them instead of guessing which one was meant.
    act = action
    if error.nil? && act && (arity = ACTION_ARITY[act]?) && rest.size > arity
      extra = rest[arity..]
      plural = extra.size > 1 ? "s" : ""
      error = "Unexpected argument#{plural}: #{extra.join(", ")}. Usage: #{usage_for(act)}"
    end

    Parsed.new(action: action, rest: rest, help: help, error: error)
  end

  # A leading `-` marks an option — except on a bare negative number,
  # which is a plausible (if invalid) `purge <days>` value. Routing `-5`
  # to the positional slot lets `parse_days` explain the real problem
  # ("must be a positive integer") instead of "Unknown option: -5".
  def self.flag?(arg : String) : Bool
    arg.starts_with?("-") && arg.to_i?.nil?
  end

  # Single-line usage for one action, used in surplus-argument errors.
  def self.usage_for(action : String) : String
    action == "purge" ? "noir cache purge <days>" : "noir cache #{action}"
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
    when "info"  then print_info
    when "clear" then clear
    when "purge" then purge(parsed.rest)
    else
      Noir::CLI.die("Unknown cache action: #{parsed.action}. Valid: #{ACTIONS.join(", ")}.")
    end
  rescue ex : File::Error
    # `Dir.children` raises (rather than returning empty) when the cache
    # directory or an ancestor can't be read — a permission-denied parent,
    # a stale mount. Fail like every other subcommand: one clean line, not
    # a raw Crystal stack trace.
    Noir::CLI.die("Cannot access the cache directory: #{ex.message}")
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
    if stats.orphans > 0
      io.puts "Incomplete:      #{stats.orphans} stranded write#{stats.orphans == 1 ? "" : "s"} " \
              "(#{format_bytes(stats.orphan_bytes)}) — reclaim with `noir cache clear`"
    end
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
    msg += orphan_note(outcome)
    msg += " (#{outcome.failed} failed)" if outcome.failed > 0
    io.puts msg
  end

  # Reclaimed temp files are reported apart from the entry count so
  # "Removed N cache entries" keeps meaning N usable cached responses.
  def self.orphan_note(outcome : LLM::Cache::DeleteOutcome) : String
    return "" if outcome.orphans < 1
    " Also reclaimed #{outcome.orphans} incomplete write#{outcome.orphans == 1 ? "" : "s"}."
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
    msg += orphan_note(outcome)
    msg += " (#{outcome.failed} failed)" if outcome.failed > 0
    io.puts msg
  end

  # Public so the unit ladder (B/KB/MB/GB) can be exercised directly,
  # matching the testability philosophy the rest of this module follows.
  #
  # The unit decision compares against the *rounded* value, not the raw
  # one: just below a 1024 boundary the raw value stays under 1024 while
  # rounding to one decimal lands on 1024.0, which printed as e.g.
  # "1024.0 KB" instead of rolling over to "1.0 MB".
  def self.format_bytes(bytes : Int64) : String
    return "#{bytes} B" if bytes < 1024
    kb = bytes / 1024.0
    return "#{kb.round(1)} KB" if kb.round(1) < 1024
    mb = kb / 1024.0
    return "#{mb.round(1)} MB" if mb.round(1) < 1024
    "#{(mb / 1024.0).round(2)} GB"
  end

  # Public for the same reason as `format_bytes`. Clamps to 0 for a
  # future-dated `t` (clock skew, an NTP jump, a manually `touch`'d
  # file) so the display never shows a negative "-3599s ago" that reads
  # like a parsing bug.
  def self.format_age(t : Time) : String
    seconds = (Time.utc - t.to_utc).total_seconds.to_i64
    seconds = 0_i64 if seconds < 0
    return "#{seconds}s" if seconds < 60
    minutes = seconds // 60
    return "#{minutes}m" if minutes < 60
    hours = minutes // 60
    return "#{hours}h" if hours < 24
    days = hours // 24
    "#{days}d"
  end
end
