require "../models/passive_scan"
require "../models/logger"
require "../models/skipped_files"
require "./severity"
require "./false_positive"
require "../utils/text_file"
require "yaml"

module NoirPassiveScan
  # Pre-filter the rule set against `min_severity`. Callers should run
  # this once at scan-startup and pass the result into `detect` per
  # file, so the per-(file × rule) severity comparison is amortized
  # down to a single pass over the rule set.
  def self.filter_rules_by_severity(rules : Array(PassiveScan), min_severity : String) : Array(PassiveScan)
    rules.select { |rule| PassiveScanSeverity.meets_threshold?(rule.info.severity, min_severity) }
  end

  # Runs every supplied rule against `file_content`. The only side effect
  # is recording a rule that raised (see `record_rule_failure`).
  # Callers are responsible for pre-filtering by severity (see
  # `filter_rules_by_severity`). Returns an empty array (no allocation
  # beyond the literal) when there are no rules to run, so callers can
  # short-circuit on `passive_scans.empty?` before reading the file.
  #
  # `file_content` must be valid UTF-8 — the scan reads it through
  # `Noir::TextFile.read` — because matching skips PCRE2's per-call
  # re-validation (`Noir::TextFile::MATCH_OPTIONS`).
  #
  # Each matcher keeps its own whole-file pre-check. Folding every rule's
  # patterns into one alternation looks cheaper but measured ~6x slower:
  # the union has no common first byte, so PCRE2 loses the literal-prefix
  # skip that lets each separate matcher jump straight to candidates.
  #
  # Pass a nil `logger` to run silently — the detect walk runs this on its
  # read threads and logs the matches itself, in walk order.
  def self.detect(file_path : String, file_content : String, rules : Array(PassiveScan), logger : NoirLogger?) : Array(PassiveScanResult)
    results = [] of PassiveScanResult
    return results if rules.empty?

    rules.each do |rule|
      # Per rule, so one rule that raises (PCRE2's match limit on a
      # catastrophically backtracking pattern) costs only its own findings
      # for this file. Uncaught, it unwound the whole file and took every
      # other rule's results with it — including real secrets from rules
      # that had already matched.
      detect_rule(rule, file_path, file_content, logger, results)
    rescue ex
      record_rule_failure(rule, file_path, ex)
    end

    results
  end

  # Not a silent skip: a rule that could not finish on a file is a coverage
  # gap, so it lands in `errors` (and `--strict`) next to the other drop
  # paths. The rule id rides in the path slot so the example list names
  # which rule failed where, not just the file.
  private def self.record_rule_failure(rule : PassiveScan, file_path : String, ex : Exception) : Nil
    Noir::SkippedFiles.record(Noir::SkippedFiles::PASSIVE_SCAN_SCOPE,
      "#{file_path} (rule #{rule.id})", ex.message.presence || ex.class.name,
      noun: "rule evaluation", phase: Noir::SkippedFiles::Phase::Scan)
  end

  # Runs one rule over one file, appending to `results`. Findings the rule
  # produced before raising stay in `results`: they are genuine matches.
  private def self.detect_rule(rule : PassiveScan, file_path : String, file_content : String,
                               logger : NoirLogger?, results : Array(PassiveScanResult)) : Nil
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
      return unless matchers.all? { |matcher| match_file?(file_content, matcher) }

      index = 0
      file_content.each_line do |line|
        if matchers.all? { |matcher| match_content?(line, matcher) }
          # Drop runtime indirections / placeholders and bare
          # variable-name mentions that cannot carry a checked-in
          # secret. See NoirPassiveScan::FalsePositive for the invariant.
          unless FalsePositive.suppress?(rule, line)
            unless detected_logged
              logger.try &.sub "├── Passive rule matched: #{rule.info.name}"
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
      active_matchers = matchers.select { |matcher| match_file?(file_content, matcher) }
      return if active_matchers.empty?

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
              logger.try &.sub "├── Passive rule matched: #{rule.info.name}"
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

  # The whole-file pre-gate. Word patterns are literals, so the per-line
  # test already answers "does any line match"; a line-oriented regex
  # needs its own gate (see `PassiveScan::Matcher#regex_may_match_file?`)
  # or an anchored one is pruned before the per-line loop sees it.
  #
  # The gate is only a shortcut, so a gate that hits PCRE2's match limit —
  # a pattern that backtracks across the whole file but stays cheap on
  # each line — passes and leaves the decision to the per-line loop
  # instead of costing the rule the file.
  private def self.match_file?(content : String, matcher : PassiveScan::Matcher) : Bool
    return match_content?(content, matcher) unless matcher.type == "regex"
    return false if matcher.string_patterns.empty? || matcher.regex_compile_failed?
    matcher.regex_may_match_file?(content, Noir::TextFile::MATCH_OPTIONS)
  rescue Regex::Error
    true
  end

  private def self.match_content?(content : String, matcher : PassiveScan::Matcher) : Bool
    patterns = matcher.string_patterns
    return false if patterns.empty?

    case matcher.type
    when "word"
      case matcher.condition
      when "and"
        if regexes = matcher.word_regexes
          regexes.all? { |regex| regex.matches?(content, options: Noir::TextFile::MATCH_OPTIONS) }
        else
          patterns.all? { |pattern| content.includes?(pattern) }
        end
      when "or"
        if regex = matcher.word_regex
          regex.matches?(content, options: Noir::TextFile::MATCH_OPTIONS)
        else
          patterns.any? { |pattern| content.includes?(pattern) }
        end
      else
        false
      end
    when "regex"
      # Compilation already failed at load time — there is no useful
      # work to do here, and retrying would just raise the same
      # exception on every line of every file.
      return false if matcher.regex_compile_failed?

      matcher.regex_match?(content, Noir::TextFile::MATCH_OPTIONS)
    else
      false
    end
  end
end
