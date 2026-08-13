require "./tagger"
require "./endpoint"
require "./code_locator"
require "./file_helper"
require "../utils/text_file"
require "../utils/path_scope"

struct SourceContext
  property path : String
  property line : Int32?
  property full_content : String

  # The file as lines. Every consumer of `read_source_context` immediately
  # splits `full_content` to walk backwards from the endpoint's line, and a
  # controller declares many handlers — so splitting per endpoint re-did the
  # same work once per endpoint per tagger. `read_source_context` passes the
  # tagger's cached (shared, read-only) array instead.
  getter lines : Array(String)

  def initialize(@path : String, @line : Int32?, @full_content : String, lines : Array(String)? = nil)
    @lines = lines || @full_content.split("\n")
  end
end

class FrameworkTagger < Tagger
  include FileHelper

  @base_path : String
  @base_paths : Array(String)
  @file_cache : Hash(String, String)
  @lines_cache : Hash(String, Array(String))

  def initialize(options : Hash(String, YAML::Any))
    super
    @base_paths = resolve_base_paths(options)
    @base_path = @base_paths.first
    @file_cache = Hash(String, String).new
    @lines_cache = Hash(String, Array(String)).new
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

  # Convention filters ("is this a test file?", "is this vendored?") must
  # match on this, never on the absolute path — see
  # `Noir::PathScope.base_relative`.
  def base_relative_path(path : String) : String
    Noir::PathScope.base_relative(path, @base_paths)
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
        full_content: content,
        lines: read_file_lines(path_info.path)
      )
    end

    results
  end

  def read_file(path : String) : String?
    if cached = @file_cache[path]?
      return cached
    end

    # Prefer the detector's content cache, which by this point holds
    # almost every file of the scan — the bare `File.read` this replaces
    # paid a second open for every file any tagger looked at. Analyzers
    # already read through the same cache (`Analyzer#read_file_content`),
    # so this also stops taggers being the one component that sees raw
    # bytes: on a file with invalid UTF-8 they now get the same
    # `invalid: :skip` text everything else works from.
    content = CodeLocator.instance.content_for(path) || Noir::TextFile.read(path)
    @file_cache[path] = content
    content
  rescue ex
    @logger.debug "FrameworkTagger: Failed to read file #{path}: #{ex.message}"
    nil
  end

  # `read_file` split on newlines, cached alongside it.
  #
  # Taggers walk backwards from an endpoint's line looking for decorators,
  # middleware and guard blocks, so they need the file as lines. They ask
  # once per endpoint (really once per code path per endpoint), which meant
  # re-splitting the same controller for every action it defines: on a
  # Rails app that was the single most expensive thing the `-T` pass did.
  #
  # The returned array is shared, so treat it as read-only.
  def read_file_lines(path : String) : Array(String)?
    if cached = @lines_cache[path]?
      return cached
    end

    content = read_file(path)
    return if content.nil?

    lines = content.split("\n")
    @lines_cache[path] = lines
    lines
  end

  # Find an annotation (`@PreAuthorize`, `@CrossOrigin`, `@Validated`, …) that
  # decorates the *class* declaration: it must be immediately followed —
  # skipping other annotations and blank lines — by a `class` line. Returns the
  # annotation line text.
  #
  # Shared by the JVM taggers: a class-level annotation applies to every
  # handler the class declares, and the per-endpoint backward walks stop at the
  # `public`/`class` boundary, so they can never see it on their own.
  #
  # The answer is a property of the file, not of the endpoint, but every
  # endpoint in a controller asks it — so memoize per (file, annotation) rather
  # than re-scanning the controller once per handler per annotation.
  @class_annotation_cache = Hash(Tuple(String, String), String?).new

  def class_level_annotation(path : String, lines : Array(String), annotation_name : String) : String?
    key = {path, annotation_name}
    if @class_annotation_cache.has_key?(key)
      return @class_annotation_cache[key]
    end
    @class_annotation_cache[key] = scan_class_level_annotation(lines, annotation_name)
  end

  private def scan_class_level_annotation(lines : Array(String), annotation_name : String) : String?
    lines.each_with_index do |raw, i|
      stripped = raw.strip
      next unless stripped.starts_with?(annotation_name)
      j = i + 1
      while j < lines.size
        nxt = lines[j].strip
        if nxt.empty? || nxt.starts_with?("@")
          j += 1
          next
        end
        return stripped if nxt.includes?("class ")
        break
      end
    end
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

  # The per-endpoint shape: look at each endpoint, tag in place, hand the
  # array back. Fifteen framework taggers carried a byte-identical copy of
  # this; they now declare only `check_endpoint`.
  #
  # Not every framework tagger fits it — eleven still override `perform`
  # because they need a pre-scan over the project (config files, middleware
  # registration) before the per-endpoint pass, or they group endpoints
  # first. Those keep their own.
  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end
    endpoints
  end

  # Per-endpoint hook for taggers using the inherited `perform`.
  #
  # A no-op rather than `abstract`: `FrameworkTagger` is instantiated
  # directly by its own spec and by the tagger-registry specs, so the class
  # cannot be abstract. A tagger that inherits `perform` without defining
  # this tags nothing — `spec/unit_test/tagger/framework_taggers/` covers
  # each one, so that shows up as a failing tagger spec rather than silence.
  protected def check_endpoint(endpoint : Endpoint)
  end
end
