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
    @base_path = resolve_base_path(options)
    @file_cache = Hash(String, String).new
  end

  # The CLI always wraps `base` in an Array(YAML::Any), so calling
  # `.to_s` on it produced strings like `["./app"]`. With that as the
  # prefix every `get_files_by_prefix_and_extension(@base_path, …)`
  # call quietly returned an empty list and the tagger never tagged
  # anything. The existing specs hid this because they set
  # `options["base"]` to a bare String. Handle both shapes so the
  # production array path matches the same fixtures.
  private def resolve_base_path(options : Hash(String, YAML::Any)) : String
    raw = options["base"]?
    return "" if raw.nil?

    if arr = raw.as_a?
      arr.first?.try(&.to_s) || ""
    else
      raw.to_s
    end
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
