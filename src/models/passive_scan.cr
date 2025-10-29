require "./logger"
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
    property condition : String

    def initialize(yaml : YAML::Any)
      @type = yaml["type"].as_s
      @patterns = yaml["patterns"].as_a
      @condition = yaml["condition"].as_s
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

  def valid?
    @id != "" && @info != "" && !@matchers.empty?
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
