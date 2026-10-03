require "./logger"
require "../passive_scan/severity"
require "yaml"
require "json"

struct PassiveScan
  struct Info
    include JSON::Serializable
    include YAML::Serializable
    property name : String
    property author : Array(YAML::Any)
    property severity : String
    property description : String
    property reference : Array(YAML::Any)

    def initialize(yaml : YAML::Any)
      @name = yaml["name"]?.try(&.as_s?) || yaml["name"]?.try(&.to_s) || ""
      # Left empty when absent rather than defaulted, so `validation_errors`
      # can reject it by name. Defaulting is not available here: the default
      # `--passive-scan-severity` threshold is `high`, so any default below
      # that silently filters the rule out — "Loaded 1 valid passive scan
      # rules" followed by no findings, which is the same invisible
      # false negative as the unknown-severity-includes-everything bug this
      # replaced, only pointing the other way.
      raw_severity = yaml["severity"]?.try(&.as_s?) || yaml["severity"]?.try(&.to_s) || ""
      @severity = raw_severity.downcase
      @description = yaml["description"]?.try(&.as_s?) || yaml["description"]?.try(&.to_s) || ""
      @reference = if ref_node = yaml["reference"]?
                     ref_node.as_a? || [ref_node] of YAML::Any
                   else
                     [] of YAML::Any
                   end
      @author = if author_node = yaml["author"]?
                  author_node.as_a? || [author_node] of YAML::Any
                else
                  [] of YAML::Any
                end
    end
  end

  struct Matcher
    ALLOWED_TYPES      = {"word", "regex"}
    ALLOWED_CONDITIONS = {"and", "or"}

    # Constructs `Regex.union` changes the meaning of. The union renumbers
    # capture groups, so a `\1`, `\g{1}`, `(?1)` or `(?(1)…)` in any pattern
    # but the first points at the wrong group; and under `(?x)` a `#`
    # comment runs to the end of the joined source and swallows the union's
    # closing parens, so the whole rule failed to compile. Over-matching
    # here (an escaped `\\1`) only costs the union fast path.
    UNION_UNSAFE = /\\[1-9gk]|\(\?P=|\(\?[+-]?\d|\(\?R|\(\?\(|\(\?[a-zA-Z^-]*x/

    # Constructs that make a whole-file gate unsound: absolute anchors
    # (`\A` `\z` `\Z` `\G`) hold only at the file's edges, not each line's,
    # and a `(*VERB)` can change newline handling or matching outright. A
    # pattern carrying one gets no gate and is left to the per-line loop.
    #
    # Lookarounds, atomic groups and possessive quantifiers keep the plain
    # gate: at a line edge they see the `\n` where the per-line match sees
    # the end of the string, which only differs for a construct that
    # reaches across the newline — and treating them as gate-less made a
    # gitleaks-style `(?<![A-Za-z0-9])…(?![A-Za-z0-9])` rule set walk every
    # line of every file.
    NO_FILE_GATE = /\\[AzZG]|\(\*/

    property type : String
    property patterns : Array(YAML::Any)
    # Pre-stringified patterns. detect.cr's hot path used to call
    # `pattern.to_s` per (file × line × matcher); the conversion is the
    # same every call so we do it once at load time.
    property string_patterns : Array(String)
    property condition : String
    # `or`: the single union every pattern is folded into, or nil when the
    # patterns cannot share one (see UNION_UNSAFE) and are matched one by
    # one through `compiled_regexes` instead.
    property compiled_regex : Regex?
    # One compiled regex per pattern, under either condition.
    property compiled_regexes : Array(Regex)?
    # Whole-file pre-check per pattern (see `file_gate_for`); a nil entry
    # has no safe gate and always passes. Used under `and`.
    @file_gates : Array(Regex?)?
    # The same gates folded for `or` (see `or_file_gates`): any hit means
    # the matcher may fire. nil when some pattern has no gate, so the
    # matcher always passes.
    @or_file_gates : Array(Regex)?
    # `word` patterns as escaped literal regexes: one union for `or`,
    # one regex per pattern for `and`. A literal regex matches exactly
    # where `String#includes?` does, and PCRE2 (with
    # `Noir::TextFile::MATCH_OPTIONS`) scans a whole file far faster
    # than `includes?`'s rolling hash, which restarts per pattern.
    getter word_regex : Regex?
    getter word_regexes : Array(Regex)?
    # Why this matcher's regexes failed to compile, or nil when they
    # compiled. Held as the message rather than a bare flag so the
    # loader can name the pattern in the warning it prints — the
    # previous shape wrote the reason straight to Crystal's global
    # `Log`, whose default backend is STDOUT, so it landed in the
    # middle of `-f json` / `-f sarif` output and broke every
    # downstream parser.
    getter regex_error : String?

    def initialize(yaml : YAML::Any)
      raw_type = yaml["type"]?.try(&.as_s?) || yaml["type"]?.try(&.to_s) || ""
      @type = raw_type.downcase
      @patterns = if patterns_node = yaml["patterns"]?
                    patterns_node.as_a? || [patterns_node] of YAML::Any
                  else
                    [] of YAML::Any
                  end
      @string_patterns = @patterns.map(&.to_s)
      raw_condition = yaml["condition"]?.try(&.as_s?) || yaml["condition"]?.try(&.to_s) || "or"
      @condition = raw_condition.downcase

      if @type == "regex" && ALLOWED_CONDITIONS.includes?(@condition)
        begin
          @compiled_regexes = @string_patterns.map { |p| Regex.new(p) }
        rescue ex
          @compiled_regexes = nil
          @regex_error = "#{ex.message} (#{ex.class}); patterns=#{@string_patterns.inspect}"
        end
        if regexes = @compiled_regexes
          @compiled_regex = union_of(regexes) if @condition == "or"
          gates = @string_patterns.map_with_index { |pattern, idx| file_gate_for(pattern, regexes[idx]) }
          @file_gates = gates
          @or_file_gates = or_file_gates(regexes, gates) if @condition == "or"
        end
      elsif @type == "word" && !@string_patterns.empty?
        # Escaped literals cannot fail to compile, but a pathological
        # pattern list could still exceed PCRE2's size limits; leave the
        # regexes nil and `match_content?` falls back to `includes?`.
        begin
          case @condition
          when "or"  then @word_regex = Regex.union(@string_patterns)
          when "and" then @word_regexes = @string_patterns.map { |p| Regex.new(Regex.escape(p)) }
          end
        rescue
          @word_regex = nil
          @word_regexes = nil
        end
      end
    end

    # One regex for every pattern when that is faithful to matching them
    # one by one; nil otherwise. Each pattern already compiled alone, so a
    # union that fails to compile (duplicate group names across patterns)
    # is a union problem, not a rule problem.
    private def union_of(regexes : Array(Regex)) : Regex?
      return regexes.first if regexes.size == 1
      return if @string_patterns.any?(&.matches?(UNION_UNSAFE))
      Regex.union(regexes)
    rescue
      nil
    end

    # The whole-file pre-check for one pattern, or nil when it has none
    # that is safe. detect.cr runs it over the whole file to skip rules
    # that cannot fire on any line, so it must accept every file in which
    # some line matches. Without MULTILINE, `^` and `$` anchor to the file
    # rather than the line, and an anchored rule only ever fired on the
    # first or last line; `(*ANYCRLF)` keeps `$` true before the `\r\n`
    # that `each_line` strips.
    private def file_gate_for(pattern : String, line_regex : Regex) : Regex?
      return if pattern.matches?(NO_FILE_GATE)
      return line_regex unless self.class.line_anchored?(pattern)
      Regex.new("(*ANYCRLF)#{pattern}", Regex::Options::MULTILINE_ONLY)
    rescue
      nil
    end

    # Folds an `or` matcher's per-pattern gates into as few whole-file scans
    # as is sound: the patterns whose gate is the pattern itself share one
    # union (the matcher's own union when that is all of them), and only
    # the MULTILINE gates of anchored patterns run on their own. nil when a
    # pattern has no gate — the matcher can then fire anywhere.
    private def or_file_gates(regexes : Array(Regex), gates : Array(Regex?)) : Array(Regex)?
      return if gates.any?(Nil)
      plain = [] of Regex
      multiline = [] of Regex
      gates.each_with_index do |gate, idx|
        next unless gate
        gate.same?(regexes[idx]) ? plain << gate : multiline << gate
      end

      folded = [] of Regex
      if (union = @compiled_regex) && plain.size == regexes.size
        folded << union
      elsif @compiled_regex && plain.size > 1
        # The full union compiled, so none of these patterns is
        # union-unsafe and their subset folds the same way.
        begin
          folded << Regex.union(plain)
        rescue
          folded.concat(plain)
        end
      else
        folded.concat(plain)
      end
      folded.concat(multiline)
    end

    # True when `pattern` has an unescaped `^` or `$` outside a character
    # class. A misread here only costs a MULTILINE gate, which still accepts
    # every line the pattern can match.
    def self.line_anchored?(pattern : String) : Bool
      chars = pattern.chars
      escaped = false
      class_start = nil
      chars.each_with_index do |char, idx|
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif start = class_start
          # `]` straight after `[` or `[^` is a member, not the close.
          first_member = chars[start + 1]? == '^' ? start + 2 : start + 1
          class_start = nil if char == ']' && idx > first_member
        elsif char == '['
          class_start = idx
        elsif char == '^' || char == '$'
          return true
        end
      end
      false
    end

    # Whole-file form of `regex_match?`: false only when no line of
    # `content` can satisfy this matcher.
    def regex_may_match_file?(content : String, options : Regex::MatchOptions = Regex::MatchOptions::None) : Bool
      gates = @file_gates
      return false if gates.nil? || gates.empty?

      case @condition
      when "or"
        if or_gates = @or_file_gates
          or_gates.any?(&.matches?(content, options: options))
        else
          true
        end
      when "and"
        gates.all? { |gate| gate.nil? || gate.matches?(content, options: options) }
      else
        false
      end
    end

    # Whether a `regex` matcher fires on `content` (a line, as detect.cr
    # calls it). Shared with the false-positive gate so both agree on what
    # fired.
    def regex_match?(content : String, options : Regex::MatchOptions = Regex::MatchOptions::None) : Bool
      regexes = @compiled_regexes
      return false if regexes.nil? || regexes.empty?

      case @condition
      when "or"
        if union = @compiled_regex
          union.matches?(content, options: options)
        else
          regexes.any?(&.matches?(content, options: options))
        end
      when "and"
        regexes.all?(&.matches?(content, options: options))
      else
        false
      end
    end

    # True when this matcher's regexes failed to compile. detect.cr
    # checks it to short-circuit instead of retrying the
    # (already-broken) compilation on every line.
    def regex_compile_failed? : Bool
      !@regex_error.nil?
    end

    def validation_errors : Array(String)
      errors = [] of String
      errors << "invalid type #{@type.inspect} (expected 'word' or 'regex')" unless ALLOWED_TYPES.includes?(@type)
      errors << "invalid condition #{@condition.inspect} (expected 'and' or 'or')" unless ALLOWED_CONDITIONS.includes?(@condition)
      errors << "missing or empty 'patterns'" if @patterns.empty? || @string_patterns.empty?
      # An empty pattern string matches every line of every scanned file —
      # `"".includes?("")` is true and `Regex.new("")` matches anywhere — so
      # one stray list entry (`- ` with nothing after it, which YAML reads
      # as null, or an explicit `''`) turns the rule into a finding per
      # source line. Reject it rather than let it flood the report.
      blank = [] of Int32
      @string_patterns.each_with_index { |pattern, idx| blank << idx if pattern.empty? }
      unless blank.empty?
        errors << "empty pattern at #{blank.size > 1 ? "indexes" : "index"} #{blank.join(", ")} (an empty pattern matches every line)"
      end
      errors
    end

    def valid? : Bool
      validation_errors.empty?
    end
  end

  ALLOWED_MATCHERS_CONDITIONS = {"and", "or"}

  property id : String
  property info : Info
  property matchers_condition : String
  property matchers : Array(Matcher)
  property category : String
  property techs : Array(YAML::Any)

  def initialize(yaml : YAML::Any)
    @id = yaml["id"]?.try(&.as_s?) || yaml["id"]?.try(&.to_s) || ""
    @info = if info_yaml = yaml["info"]?
              Info.new(info_yaml)
            else
              Info.new(YAML::Any.new({} of YAML::Any => YAML::Any))
            end
    @matchers = if matchers_yaml = yaml["matchers"]?.try(&.as_a?)
                  matchers_yaml.map { |matcher| Matcher.new(matcher) }
                else
                  [] of Matcher
                end
    raw_matchers_condition = yaml["matchers-condition"]?.try(&.as_s?) || yaml["matchers-condition"]?.try(&.to_s) || "or"
    @matchers_condition = raw_matchers_condition.downcase
    @category = yaml["category"]?.try(&.as_s?) || yaml["category"]?.try(&.to_s) || ""
    @techs = if techs_yaml = yaml["techs"]?
               techs_yaml.as_a? || [techs_yaml] of YAML::Any
             else
               [] of YAML::Any
             end
  end

  def validation_errors : Array(String)
    errors = [] of String
    errors << "missing or empty 'id'" if @id.empty?
    errors << "missing or empty 'info.name'" if @info.name.empty?
    if @info.severity.empty?
      errors << "missing 'info.severity' (expected #{PassiveScanSeverity.valid_levels.join(", ")})"
    elsif !PassiveScanSeverity.valid?(@info.severity)
      errors << "invalid severity #{@info.severity.inspect} (expected #{PassiveScanSeverity.valid_levels.join(", ")})"
    end
    errors << "missing or empty 'matchers'" if @matchers.empty?
    errors << "invalid matchers-condition #{@matchers_condition.inspect} (expected 'and' or 'or')" unless ALLOWED_MATCHERS_CONDITIONS.includes?(@matchers_condition)
    @matchers.each_with_index do |matcher, idx|
      matcher.validation_errors.each do |err|
        errors << "matcher[#{idx}]: #{err}"
      end
    end
    # A rule whose matchers cannot compile is not "loaded but quiet" —
    # it is a rule that can never fire, which reads to the user exactly
    # like a clean scan. Counting it among the "Loaded N valid passive
    # scan rules" is the invisible-zero-coverage case `rules.cr` already
    # guards against for a mis-pointed rules directory.
    errors << "no matcher can ever fire: #{dead_matcher_reasons.join("; ")}" if never_matches?
    errors
  end

  # Non-fatal load problems: a broken matcher the rule can still fire
  # without (an `or` rule with one good matcher left). Reported so the
  # rule's reduced coverage is visible instead of silent.
  def load_warnings : Array(String)
    return [] of String if never_matches?
    @matchers.each_with_index.compact_map do |matcher, idx|
      if err = matcher.regex_error
        "matcher[#{idx}] regex did not compile and will never match: #{err}"
      end
    end.to_a
  end

  # True when no input can satisfy the rule because of dead matchers:
  # under `and` every matcher must hit, so one dead matcher is fatal;
  # under `or` the rule survives while a single matcher still compiles.
  private def never_matches? : Bool
    return false if @matchers.empty?
    if @matchers_condition == "and"
      @matchers.any?(&.regex_compile_failed?)
    else
      @matchers.all?(&.regex_compile_failed?)
    end
  end

  private def dead_matcher_reasons : Array(String)
    @matchers.each_with_index.compact_map do |matcher, idx|
      if err = matcher.regex_error
        "matcher[#{idx}]: #{err}"
      end
    end.to_a
  end

  # A rule is usable when it has an id, a non-empty info name, at
  # least one matcher, all matchers are valid (allowed type, condition,
  # non-empty patterns), valid severity, matchers_condition is 'and' or
  # 'or', and at least one matcher can actually fire.
  def valid? : Bool
    validation_errors.empty?
  end
end

struct PassiveScanResult
  include JSON::Serializable
  include YAML::Serializable
  property id, info, category, techs, file_path, line_number, extract

  def initialize(passive_scan : PassiveScan, file_path : String, line_number : Int32, extract : String)
    @id = passive_scan.id
    @info = passive_scan.info
    @category = passive_scan.category
    @techs = passive_scan.techs
    @file_path = file_path
    @line_number = line_number
    @extract = extract
  end
end
