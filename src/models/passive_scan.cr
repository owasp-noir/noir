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
      @name = yaml["name"].as_s
      @severity = yaml["severity"].as_s
      @description = yaml["description"].as_s
      @reference = yaml["reference"].as_a
      @author = yaml["author"].as_a
    end
  end

  struct Matcher
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
      @type = yaml["type"].as_s
      @patterns = yaml["patterns"].as_a
      @string_patterns = @patterns.map(&.to_s)
      @condition = yaml["condition"].as_s
      @regex_compile_failed = false

      if @type == "regex"
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
  end

  property id : String
  property info : Info
  property matchers_condition : String
  property matchers : Array(Matcher)
  property category : String
  property techs : Array(YAML::Any)

  def initialize(yaml : YAML::Any)
    @id = yaml["id"].as_s
    @info = Info.new(yaml["info"])
    @matchers = yaml["matchers"].as_a.map { |matcher| Matcher.new(matcher) }
    @matchers_condition = yaml["matchers-condition"].to_s
    @category = yaml["category"].as_s
    @techs = yaml["techs"].as_a
  end

  # A rule is usable when it has an id, a non-empty info name, and at
  # least one matcher. The earlier `@info != ""` check compared an
  # Info struct against a String, which is always true and therefore a
  # no-op; the rewrite checks `@info.name` instead so rules with an
  # empty name (effectively unusable for SARIF / human output) are
  # dropped during load.
  def valid?
    !@id.empty? && !@info.name.empty? && !@matchers.empty?
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
