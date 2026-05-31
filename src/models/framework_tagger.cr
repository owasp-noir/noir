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
  @base_paths : Array(String)
  @file_cache : Hash(String, String)

  def initialize(options : Hash(String, YAML::Any))
    super
    @base_paths = resolve_base_paths(options)
    @base_path = @base_paths.first
    @file_cache = Hash(String, String).new
  end

  # `base` is built as a flat Array(YAML::Any) and `-b PATH` / positional
  # args are repeatable (`noir scan ./a ./b`), so every other consumer
  # reads ALL of them. Collapsing to the first path made framework-tagger
  # pre-scans miss auth config/middleware living under any later base —
  # a silent false negative for multi-root scans. Resolve every base path
  # (and keep `@base_path` as the first for callers that still want one).
  #
  # An empty/nil `base` falls back to `[""]`: `get_files_by_prefix_and_extension`
  # treats `""` as "match every path", preserving the prior no-filter
  # behaviour. Bare-String `base` (used by specs) is handled too.
  private def resolve_base_paths(options : Hash(String, YAML::Any)) : Array(String)
    raw = options["base"]?
    return [""] if raw.nil?

    if arr = raw.as_a?
      paths = arr.map(&.to_s).reject(&.empty?)
      paths.empty? ? [""] : paths
    else
      [raw.to_s]
    end
  end

  # Collect files with the given extension across every configured base
  # path, so a multi-root scan sees auth config under all of them.
  def collect_files_by_extension(extension : String) : Array(String)
    files = [] of String
    @base_paths.each do |base|
      files.concat(get_files_by_prefix_and_extension(base, extension))
    end
    files.uniq!
    files
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
