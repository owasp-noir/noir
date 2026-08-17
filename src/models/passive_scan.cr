require "./logger"
require "yaml"
require "json"
require "log"

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
      @severity = yaml["severity"]?.try(&.as_s?) || yaml["severity"]?.try(&.to_s) || "info"
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
    # Sticky flag: true when this matcher's regexes failed to compile.
    # detect.cr checks it to short-circuit instead of retrying the
    # (already-broken) compilation on every line.
    property? regex_compile_failed : Bool

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
      @regex_compile_failed = false

      if !ALLOWED_TYPES.includes?(@type)
        Log.warn { "Passive scan matcher has invalid type: #{@type.inspect} (expected 'word' or 'regex')" }
      end

      if !ALLOWED_CONDITIONS.includes?(@condition)
        Log.warn { "Passive scan matcher has invalid condition: #{@condition.inspect} (expected 'and' or 'or')" }
      end

      if @type == "regex" && ALLOWED_CONDITIONS.includes?(@condition)
        if @condition == "or"
          begin
            @compiled_regex = Regex.union(@string_patterns.map { |p| Regex.new(p) })
          rescue ex
            Log.warn { "Passive scan matcher regex compilation (or-union) failed: #{ex.message} (#{ex.class}); patterns=#{@string_patterns.inspect}" }
            @compiled_regex = nil
            @regex_compile_failed = true
          end
        elsif @condition == "and"
          begin
            @compiled_regexes = @string_patterns.map { |p| Regex.new(p) }
          rescue ex
            Log.warn { "Passive scan matcher regex compilation (and-case) failed: #{ex.message} (#{ex.class}); patterns=#{@string_patterns.inspect}" }
            @compiled_regexes = nil
            @regex_compile_failed = true
          end
        end
      end
    end

    def valid? : Bool
      ALLOWED_TYPES.includes?(@type) &&
        ALLOWED_CONDITIONS.includes?(@condition) &&
        !@patterns.empty? &&
        !@string_patterns.empty?
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

    if !ALLOWED_MATCHERS_CONDITIONS.includes?(@matchers_condition)
      Log.warn { "Passive scan rule #{@id.inspect} has invalid matchers-condition: #{@matchers_condition.inspect} (expected 'and' or 'or')" }
    end
  end

  # A rule is usable when it has an id, a non-empty info name, at
  # least one matcher, all matchers are valid (allowed type, condition,
  # non-empty patterns), and matchers_condition is 'and' or 'or'.
  def valid? : Bool
    !@id.empty? &&
      !@info.name.empty? &&
      !@matchers.empty? &&
      @matchers.all?(&.valid?) &&
      ALLOWED_MATCHERS_CONDITIONS.includes?(@matchers_condition)
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
