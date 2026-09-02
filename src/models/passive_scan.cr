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

    property type : String
    property patterns : Array(YAML::Any)
    # Pre-stringified patterns. detect.cr's hot path used to call
    # `pattern.to_s` per (file × line × matcher); the conversion is the
    # same every call so we do it once at load time.
    property string_patterns : Array(String)
    property condition : String
    property compiled_regex : Regex?
    property compiled_regexes : Array(Regex)?
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
        if @condition == "or"
          begin
            @compiled_regex = Regex.union(@string_patterns.map { |p| Regex.new(p) })
          rescue ex
            @compiled_regex = nil
            @regex_error = "#{ex.message} (#{ex.class}); patterns=#{@string_patterns.inspect}"
          end
        elsif @condition == "and"
          begin
            @compiled_regexes = @string_patterns.map { |p| Regex.new(p) }
          rescue ex
            @compiled_regexes = nil
            @regex_error = "#{ex.message} (#{ex.class}); patterns=#{@string_patterns.inspect}"
          end
        end
      end
    end

    # True when this matcher's regexes failed to compile. detect.cr
    # checks it to short-circuit instead of retrying the
    # (already-broken) compilation on every line.
    def regex_compile_failed? : Bool
      !@regex_error.nil?
    end

    # True when this matcher can never produce a hit: its regexes did
    # not compile, so `match_content?` returns false for every input.
    def dead? : Bool
      regex_compile_failed?
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
      @matchers.any?(&.dead?)
    else
      @matchers.all?(&.dead?)
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
