require "../utils/path_scope"
require "../utils/utils"
require "./logger"
require "./locator_key"

class CodeLocator
  @@instance : CodeLocator? = nil

  # Default content cache budget (bytes). Override via
  # `NOIR_CONTENT_CACHE_MAX_MB` (value in megabytes). Set to 0 or the
  # env `NOIR_CONTENT_CACHE_DISABLE=true` to disable caching entirely,
  # in which case `content_for` always returns nil and analyzers fall
  # through to `File.read`.
  DEFAULT_CONTENT_CACHE_BUDGET = 512_i64 * 1024 * 1024

  @logger : NoirLogger
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @s_map : Hash(String, String)
  @a_map : Hash(String, Array(String))
  @extension_index : Hash(String, Array(String))
  @extension_index_built : Bool
  @basename_index : Hash(String, Array(String))
  @basename_index_built : Bool
  @file_contents : Hash(String, String)
  @content_cache_budget : Int64
  @content_cache_used : Int64
  @content_cache_skipped : Int32
  @expanded_file_map : Array(Tuple(String, String))?
  @expanded_path_index : Hash(String, String)?
  @scan_base_paths : Array(String)

  @lock : Mutex

  def initialize
    options = {"debug" => "false", "verbose" => "false", "color" => "true", "nolog" => "false"}
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log

    @s_map = Hash(String, String).new
    @a_map = Hash(String, Array(String)).new
    @extension_index = Hash(String, Array(String)).new
    @extension_index_built = false
    @basename_index = Hash(String, Array(String)).new
    @basename_index_built = false

    @file_contents = Hash(String, String).new
    @content_cache_budget = resolve_content_cache_budget
    @content_cache_used = 0_i64
    @content_cache_skipped = 0
    @expanded_file_map = nil
    @expanded_path_index = nil
    @scan_base_paths = [] of String
    @lock = Mutex.new
  end

  # The `-b` roots of the current scan, published once by `NoirRunner`.
  #
  # Convention filters ("is this file under `tests/`?", "is this bundled
  # output?") must run on the path *relative to the scan base*, never on
  # the absolute path — otherwise a directory above the base decides the
  # result and the same source tree reports different endpoints depending
  # on where it is checked out. Analyzers get that through
  # `Analyzer#base_relative_path`; the shared parser layer
  # (`Noir::JSRouteExtractor` and friends) has no analyzer instance, so it
  # reads the roots from here.
  def scan_base_paths=(paths : Array(String))
    @scan_base_paths = paths.reject(&.empty?)
  end

  def scan_base_paths : Array(String)
    @scan_base_paths
  end

  # `path` relative to the scan base that owns it, `/`-separated and
  # rooted with a leading `/`. With no registered bases (library callers,
  # unit specs that drive a parser directly) the path is returned
  # unchanged, which is exactly the pre-registry behaviour.
  def base_relative(path : String) : String
    return path if @scan_base_paths.empty?
    Noir::PathScope.base_relative(path, @scan_base_paths)
  end

  # Megabyte figures at or above this overflow `Int64` once scaled to bytes.
  # Crystal checks integer arithmetic, so the multiply below *raised* rather
  # than wrapping: `NOIR_CONTENT_CACHE_MAX_MB=99999999999999` aborted the whole
  # scan with an unhandled `OverflowError` stack trace before the first file
  # was read. Saturate instead — a budget that large already means "cache
  # everything", which is exactly what `Int64::MAX` gives.
  MAX_CONTENT_CACHE_MB = Int64::MAX // (1024_i64 * 1024)

  private def resolve_content_cache_budget : Int64
    return 0_i64 if any_to_bool(ENV["NOIR_CONTENT_CACHE_DISABLE"]?)
    if raw = ENV["NOIR_CONTENT_CACHE_MAX_MB"]?
      parsed = raw.to_i64?
      if parsed && parsed >= 0
        return parsed >= MAX_CONTENT_CACHE_MB ? Int64::MAX : parsed * 1024 * 1024
      end
    end
    DEFAULT_CONTENT_CACHE_BUDGET
  end

  def self.instance : CodeLocator
    @@instance ||= new
  end

  def set(key : Noir::LocatorKey(String), value : String)
    @s_map[key.name] = value
  end

  # `String?` rather than the old `(String | Array(String))`: the union only
  # existed because a bare string key carried no type, so `get` could not
  # promise which map it was reading. Its one caller worked around it by
  # interpolating the result.
  def get(key : Noir::LocatorKey(String)) : String?
    @s_map[key.name]?
  end

  def push(key : Noir::LocatorKey(Array(String)), value : String)
    @a_map[key.name] ||= Array(String).new
    @a_map[key.name] << value
  end

  # The scanned-file registry.
  #
  # `file_map` was never a blackboard key like the other 64. It is a file
  # registry with four derived views (`@extension_index`, `@basename_index`,
  # `@expanded_file_map`, `@expanded_path_index`) plus a content cache bolted
  # to it, and it was the only reason `push` and `clear` each carried an
  # `if key == "file_map"` branch. Giving it methods makes the coupling
  # structural instead of a string comparison that behaves differently in two
  # places.
  private FILE_MAP = "file_map"

  # Register a path with no content — the detector's content-free fast path,
  # for files nothing will read during detection or passive scan.
  #
  # Invalidates the four derived views but deliberately NOT `@file_contents`.
  # A newly registered path has no cached content to invalidate, and dropping
  # the cache here would throw away every file read so far. `content_for`
  # returning nil for a registered path is the contract — `register_file`
  # skips over-budget files the same way — so callers keep a `File.read`
  # fallback regardless.
  def register_path(path : String)
    @a_map[FILE_MAP] ||= Array(String).new
    @a_map[FILE_MAP] << path
    invalidate_file_views
  end

  # Every registered path, in registration order.
  def all_files : Array(String)
    @a_map[FILE_MAP]? || Array(String).new
  end

  # Forget every registered file, its cached content, and every derived view.
  def reset_files
    @a_map.delete(FILE_MAP)
    @file_contents.clear
    @content_cache_used = 0_i64
    @content_cache_skipped = 0
    invalidate_file_views
  end

  # The memoised views are rebuilt on next read; the indexes sit behind a
  # `_built` flag, so a lookup taken before a later registration would
  # otherwise keep serving the older file list.
  private def invalidate_file_views
    @expanded_file_map = nil
    @expanded_path_index = nil
    @extension_index_built = false
    @basename_index_built = false
  end

  # One-shot used by the detector's file reader: push the path into
  # `file_map` and (budget permitting) cache the content so analyzers
  # can skip the second `File.read`. Files whose content exceeds the
  # remaining budget are still registered in `file_map` but not cached,
  # and `content_for(path)` returns `nil` for them — callers must keep
  # a `File.read` fallback.
  def register_file(path : String, content : String)
    register_path(path)

    return if @content_cache_budget <= 0
    size = content.bytesize.to_i64
    if @content_cache_used + size > @content_cache_budget
      @content_cache_skipped += 1
      return
    end
    @file_contents[path] = content
    @content_cache_used += size
  end

  # Returns cached file content or `nil` if the file was not cached
  # (budget exhausted, caching disabled, or read after cache was
  # cleared). Callers should fall back to `File.read` on `nil`.
  def content_for(path : String) : String?
    @file_contents[path]?
  end

  def content_cache_stats : NamedTuple(bytes: Int64, files: Int32, skipped: Int32, budget: Int64)
    {bytes: @content_cache_used, files: @file_contents.size, skipped: @content_cache_skipped, budget: @content_cache_budget}
  end

  def all(key : Noir::LocatorKey(Array(String))) : Array(String)
    result = @a_map[key.name]?
    return result if result
    Array(String).new
  end

  # `{original, File.expand_path(original)}` for every file in `file_map`,
  # built once and cached. `File.expand_path` is pure string normalization
  # but non-trivial, and the monorepo helpers in `FileHelper` re-scan
  # `all_files` once per base path per analyzer — without this the same
  # path is expanded thousands of times (O(analyzers × bases × files)).
  # Invalidated whenever `file_map` changes (push / clear).
  def expanded_file_map : Array(Tuple(String, String))
    cached = @expanded_file_map
    return cached if cached

    @lock.synchronize do
      cached = @expanded_file_map
      return cached if cached

      files = @a_map[FILE_MAP]?
      built = files ? files.map { |file| {file, File.expand_path(file)} } : [] of Tuple(String, String)
      @expanded_file_map = built
      built
    end
  end

  # O(1) `path => File.expand_path(path)` lookup for files registered in
  # `file_map`. Analyzers call `path_under_root?(file, base)` inside
  # `base_paths.each { files.each { ... } }` loops, so the same file would
  # otherwise be re-expanded once per base (and `File.expand_path` of a
  # relative path issues a `getcwd`). Unregistered paths fall back to a live
  # expansion. Shares the lazy lifecycle / invalidation of `expanded_file_map`.
  def expanded_path_for(path : String) : String
    expanded_path_index[path]? || File.expand_path(path)
  end

  private def expanded_path_index : Hash(String, String)
    cached = @expanded_path_index
    return cached if cached

    # Resolve `expanded_file_map` *before* taking `@lock` — it grabs the same
    # non-reentrant mutex, so calling it inside the block below would deadlock.
    pairs = expanded_file_map
    @lock.synchronize do
      cached = @expanded_path_index
      return cached if cached

      built = {} of String => String
      pairs.each { |original, expanded| built[original] = expanded }
      @expanded_path_index = built
      built
    end
  end

  # Group every file_map entry under the key `block` derives from it.
  #
  # Shared by the extension and basename indexes, which differ only in
  # that key. Returns whether the index is now built: with no file_map
  # yet there is nothing to index and the caller leaves its `_built`
  # flag false so a later lookup retries. Callers must hold `@lock`.
  private def rebuild_path_index(index : Hash(String, Array(String)), & : String -> String) : Bool
    index.clear
    files = @a_map[FILE_MAP]?
    return false unless files
    files.each do |file|
      (index[yield file] ||= Array(String).new) << file
    end
    true
  end

  # Build extension index from file_map for fast lookups
  def build_extension_index
    return if @extension_index_built
    @lock.synchronize do
      return if @extension_index_built
      @extension_index_built = rebuild_path_index(@extension_index) { |file| File.extname(file) }
    end
  end

  # Get files by extension using the index (O(1) lookup)
  def files_by_extension(extension : String) : Array(String)
    build_extension_index
    @extension_index[extension]? || Array(String).new
  end

  # Build a `basename => paths` index from file_map.
  #
  # The companion to `build_extension_index`, for the "find the file(s)
  # whose path ends with `a/b/c.py`" lookups that analyzers otherwise
  # answer with `Dir.glob("root/**/a/b/c.py")`. That glob walks the whole
  # tree from the scan root — descending into `node_modules`, `.git` and
  # every other subtree the detector deliberately pruned — and costs one
  # `opendir`/`getdirentries` pass per call. Django's ROOT_URLCONF
  # resolution ran it once per `settings.py`, which on a 44k-file
  # monorepo was ~73% of the entire analysis phase.
  #
  # Keyed on basename because that is the selective part of those
  # patterns: `urls.py` narrows 44k files to a handful, and the caller
  # confirms the rest of the path with a cheap `ends_with?`.
  def build_basename_index
    return if @basename_index_built
    @lock.synchronize do
      return if @basename_index_built
      @basename_index_built = rebuild_path_index(@basename_index) { |file| File.basename(file) }
    end
  end

  # Files whose basename is exactly `basename` (O(1) lookup).
  def files_by_basename(basename : String) : Array(String)
    build_basename_index
    @basename_index[basename]? || Array(String).new
  end

  def clear(key : Noir::LocatorKey)
    @s_map.delete(key.name)
    @a_map.delete(key.name)
  end

  # Drops every runtime-minted key under `ns`. Runs at a phase boundary with
  # no fibers in flight, so a plain reject is enough — no minted-key
  # bookkeeping to maintain.
  def clear_namespace(ns : Noir::LocatorKeyNamespace)
    @a_map.reject! { |name, _| ns.matches?(name) }
    @s_map.reject! { |name, _| ns.matches?(name) }
  end

  def clear_all
    @s_map.clear
    @a_map.clear
    @extension_index.clear
    @extension_index_built = false
    @basename_index.clear
    @basename_index_built = false
    @file_contents.clear
    @content_cache_used = 0_i64
    @content_cache_skipped = 0
    @expanded_file_map = nil
    @expanded_path_index = nil
  end

  def show_table
    @logger.sub("String Map:")
    @s_map.each do |key, value|
      @logger.sub("  #{key} => #{value}")
    end
    @logger.sub("Array Map:")
    @a_map.each do |key, value|
      @logger.sub("  #{key} => #{value.size} items")
    end
  end
end
