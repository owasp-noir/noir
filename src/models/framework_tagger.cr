require "./tagger"
require "./endpoint"
require "./code_locator"
require "./file_helper"

struct SourceContext
  property path : String
  property line : Int32?
  property full_content : String

  def initialize(@path : String, @line : Int32?, @full_content : String)
  end
end

class FrameworkTagger < Tagger
  include FileHelper

  @base_path : String
  @file_cache : Hash(String, String)

  def initialize(options : Hash(String, YAML::Any))
    super
    @base_path = options["base"].to_s
    @file_cache = Hash(String, String).new
  end

  def self.target_techs : Array(String)
    [] of String
  end

  def read_source_context(endpoint : Endpoint) : Array(SourceContext)
    results = [] of SourceContext

    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      results << SourceContext.new(
        path: path_info.path,
        line: path_info.line,
        full_content: content
      )
    end

    results
  end

  def read_file(path : String) : String?
    if cached = @file_cache[path]?
      return cached
    end

    content = File.read(path)
    @file_cache[path] = content
    content
  rescue ex
    @logger.debug "FrameworkTagger: Failed to read file #{path}: #{ex.message}"
    nil
  end
end
