require "./logger"
require "./endpoint"
require "./code_locator"
require "./file_helper"

struct SourceContext
  property path : String
  property line : Int32?
  property context : Array(String)
  property full_content : String

  def initialize(@path : String, @line : Int32?, @context : Array(String), @full_content : String)
  end
end

class FrameworkTagger
  include FileHelper

  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @name : String
  @base_path : String

  def initialize(options : Hash(String, YAML::Any))
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @options = options
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @name = ""
    @base_path = options["base"].to_s

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log
  end

  def name
    @name
  end

  def self.target_techs : Array(String)
    [] of String
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints
  end

  def read_source_context(endpoint : Endpoint, context_lines : Int32 = 30) : Array(SourceContext)
    results = [] of SourceContext

    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line = path_info.line

      if line
        start_line = [line - context_lines, 0].max
        end_line = [line + context_lines, lines.size - 1].min
        context = lines[start_line..end_line]
      else
        context = lines
      end

      results << SourceContext.new(
        path: path_info.path,
        line: line,
        context: context,
        full_content: content
      )
    end

    results
  end

  def read_file(path : String) : String?
    File.read(path)
  rescue ex
    @logger.debug "FrameworkTagger: Failed to read file #{path}: #{ex.message}"
    nil
  end
end
