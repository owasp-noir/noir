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

  # The annotation lines stacked *below* the route marker at `route_idx`,
  # down to the declaration they decorate. An endpoint's line is its route
  # marker (`@GetMapping`, `@app.route`, `#[Route]`, `@Get()`), and auth
  # markers sit on either side of it — `@GetMapping` then `@PreAuthorize` is
  # as common as the reverse — so a walk that only goes up misses half of
  # them. `marker` is what starts an annotation line (`"@"`, `"#["`); a line
  # inside an annotation's still-open brackets belongs to it, comment lines
  # are skipped, and anything else — the declaration, a blank line — ends
  # the stack.
  def annotation_lines_below(lines : Array(String), route_idx : Int32, marker : String, limit : Int32 = 15) : Array(String)
    below = [] of String
    return below unless 0 <= route_idx < lines.size
    # Below a method declaration is its body, not more annotations.
    return below unless lines[route_idx].strip.starts_with?(marker)

    depth, declared = scan_annotations(lines[route_idx], marker)
    # `@GetMapping("/x") fun x() = ...` declares the handler on the route
    # line itself, so the annotations below it belong to the next handler.
    return below if declared

    idx = route_idx + 1
    last = {route_idx + limit, lines.size - 1}.min
    while idx <= last
      current = lines[idx].strip
      if depth > 0
        below << current
        depth += bracket_balance(current)
      elsif current.starts_with?(marker)
        below << current
        depth, declared = scan_annotations(current, marker)
        break if declared
      elsif !annotation_comment?(current)
        break
      end
      idx += 1
    end
    below
  end

  # Reads the annotations a line opens with. Returns the bracket depth still
  # open at the end of the line (a multi-line annotation), and whether code
  # other than annotations and a comment follows them — a declaration
  # sharing the line.
  private def scan_annotations(line : String, marker : String) : {Int32, Bool}
    chars = line.chars
    i = 0
    loop do
      while i < chars.size && chars[i].whitespace?
        i += 1
      end
      break unless marker_at?(chars, i, marker)
      i += marker.size
      depth = 0
      if marker == "#["
        depth = 1
      else
        while i < chars.size && (chars[i].alphanumeric? || chars[i].in?('_', '.', ':'))
          i += 1
        end
        if i < chars.size && chars[i] == '('
          depth = 1
          i += 1
        end
      end
      while depth > 0 && i < chars.size
        char = chars[i]
        if char.in?('"', '\'')
          i = skip_quoted(chars, i)
          next
        end
        depth += 1 if char.in?('(', '[')
        depth -= 1 if char.in?(')', ']')
        i += 1
      end
      return {depth, false} if depth > 0
    end
    rest = chars[i..].join.strip
    {0, !(rest.empty? || annotation_comment?(rest))}
  end

  private def marker_at?(chars : Array(Char), i : Int32, marker : String) : Bool
    return false if i + marker.size > chars.size
    marker.chars.each_with_index.all? { |char, offset| chars[i + offset] == char }
  end

  # Index just past the string literal opening at `start`.
  private def skip_quoted(chars : Array(Char), start : Int32) : Int32
    quote = chars[start]
    i = start + 1
    while i < chars.size
      return i + 1 if chars[i] == quote
      i += chars[i] == '\\' ? 2 : 1
    end
    i
  end

  # Opening minus closing brackets outside string literals.
  private def bracket_balance(line : String) : Int32
    chars = line.chars
    balance = 0
    i = 0
    while i < chars.size
      char = chars[i]
      if char.in?('"', '\'')
        i = skip_quoted(chars, i)
        next
      end
      balance += 1 if char.in?('(', '[')
      balance -= 1 if char.in?(')', ']')
      i += 1
    end
    balance
  end

  private def annotation_comment?(line : String) : Bool
    line.starts_with?("//") || (line.starts_with?('#') && !line.starts_with?("#["))
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
end
