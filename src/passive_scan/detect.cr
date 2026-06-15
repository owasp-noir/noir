require "../models/passive_scan"
require "../models/logger"
require "./severity"
require "./false_positive"
require "yaml"

module NoirPassiveScan
  # Pre-filter the rule set against `min_severity`. Callers should run
  # this once at scan-startup and pass the result into `detect` per
  # file, so the per-(file × rule) severity comparison is amortized
  # down to a single pass over the rule set.
  def self.filter_rules_by_severity(rules : Array(PassiveScan), min_severity : String) : Array(PassiveScan)
    rules.select { |rule| PassiveScanSeverity.meets_threshold?(rule.info.severity, min_severity) }
  end

  # Pure detection: runs every supplied rule against `file_content`.
  # Callers are responsible for pre-filtering by severity (see
  # `filter_rules_by_severity`). Returns an empty array (no allocation
  # beyond the literal) when there are no rules to run, so callers can
  # short-circuit on `passive_scans.empty?` before reading the file.
  def self.detect(file_path : String, file_content : String, rules : Array(PassiveScan), logger : NoirLogger) : Array(PassiveScanResult)
    results = [] of PassiveScanResult
    return results if rules.empty?

    rules.each do |rule|
      matchers = rule.matchers
      # Set on the first per-line hit so the "Detected" sub-log fires
      # exactly once per (rule × file) — the previous shape logged
      # before the per-line confirmation (false positive on AND) and
      # per result (spam on OR).
      detected_logged = false

      if rule.matchers_condition == "and"
        # Necessary-but-not-sufficient gate: every matcher must appear
        # somewhere in the file. The per-line `all?` below is the real
        # confirmation.
        next unless matchers.all? { |matcher| match_content?(file_content, matcher) }

        index = 0
        file_content.each_line do |line|
          if matchers.all? { |matcher| match_content?(line, matcher) }
            # Drop runtime indirections / placeholders and bare
            # variable-name mentions that cannot carry a checked-in
            # secret. See NoirPassiveScan::FalsePositive for the invariant.
            unless FalsePositive.suppress?(rule, line)
              unless detected_logged
                logger.sub "└── Detected: #{rule.info.name}"
                detected_logged = true
              end
              results << PassiveScanResult.new(rule, file_path, index + 1, line)
            end
          end
          index += 1
        end
      else
        # OR branch: prune matchers that cannot fire on any line
        # before the per-line loop, then walk the file once checking
        # every survivor.
        active_matchers = matchers.select { |matcher| match_content?(file_content, matcher) }
        next if active_matchers.empty?

        index = 0
        file_content.each_line do |line|
          # Stop at the first matcher that fires on this line. The
          # previous shape pushed one `PassiveScanResult` per matcher
          # hit — so a rule with both `word` and `regex` matchers
          # joined by `or` (e.g. aws-access-key, github-token) would
          # emit two duplicate entries for any line that happened to
          # satisfy both matchers, even though it's the same finding.
          active_matchers.each do |matcher|
            if match_content?(line, matcher)
              # Drop runtime indirections / placeholders and bare
              # variable-name mentions that cannot carry a checked-in
              # secret. See NoirPassiveScan::FalsePositive.
              break if FalsePositive.suppress?(rule, line)
              unless detected_logged
                logger.sub "└── Detected: #{rule.info.name}"
                detected_logged = true
              end
              results << PassiveScanResult.new(rule, file_path, index + 1, line)
              break
            end
          end
          index += 1
        end
      end
    end

    results
  end

  # Backwards-compatible entry point used by existing specs. Pre-filters
  # the rule set by severity and dispatches to `detect`.
  def self.detect_with_severity(file_path : String, file_content : String, rules : Array(PassiveScan), logger : NoirLogger, min_severity : String) : Array(PassiveScanResult)
    detect(file_path, file_content, filter_rules_by_severity(rules, min_severity), logger)
  end

  private def self.match_content?(content : String, matcher : PassiveScan::Matcher) : Bool
    patterns = matcher.string_patterns
    return false if patterns.empty?

    case matcher.type
    when "word"
      case matcher.condition
      when "and"
        patterns.all? { |pattern| content.includes?(pattern) }
      when "or"
        patterns.any? { |pattern| content.includes?(pattern) }
      else
        false
      end
    when "regex"
      # Compilation already failed at load time — there is no useful
      # work to do here, and retrying would just raise the same
      # exception on every line of every file.
      return false if matcher.regex_compile_failed?

      case matcher.condition
      when "and"
        if regexes = matcher.compiled_regexes
          regexes.all? { |regex| !!content.match(regex) }
        else
          false
        end
      when "or"
        if regex = matcher.compiled_regex
          !!content.match(regex)
        else
          false
        end
      else
        false
      end
    else
      false
    end
  end
end
