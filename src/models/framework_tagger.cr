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

  # Static-asset file extensions. A route ending in one of these serves a
  # static file off the web server, not a guarded API route.
  STATIC_ASSET_EXTENSIONS = %w[
    .html .htm .js .mjs .cjs .css .map .ico .png .jpg .jpeg .gif .svg .webp
    .avif .bmp .woff .woff2 .ttf .otf .eot .wasm
  ]

  # Well-known public files served at the web root.
  STATIC_PUBLIC_FILES = Set{
    "favicon.ico", "robots.txt", "manifest.json", "asset-manifest.json",
    "sitemap.xml", "service-worker.js", "sw.js", "browserconfig.xml",
  }

  # A static-file / SPA-shell route, recognized conservatively: the SPA
  # root, a catch-all wildcard mount (`/static/*filepath`, `/*any`), a
  # well-known public file, or a static-asset extension. Taggers use this to
  # exempt such routes from broad root/global middleware scopes, where the
  # signal is noise (or a false positive for assets registered outside the
  # middleware chain) rather than a meaningful per-endpoint review target.
  def static_asset_route?(url : String) : Bool
    path = url.split("?", 2)[0].split("#", 2)[0].downcase
    return true if path == "/" || path.empty?

    segments = path.split("/").reject(&.empty?)
    # Catch-all wildcard — the shape of a static-file server / SPA fallback
    # (`r.Static`, `r.StaticFS`, a NoRoute SPA handler), not a REST route.
    return true if segments.any?(&.starts_with?("*"))

    last = segments[-1]? || ""
    return true if STATIC_PUBLIC_FILES.includes?(last)
    STATIC_ASSET_EXTENSIONS.any? { |ext| last.ends_with?(ext) }
  end
end
