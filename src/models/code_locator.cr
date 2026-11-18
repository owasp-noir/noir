require "../utils/file_extension"
require "../utils/path_scope"
require "../utils/text_file"
require "../utils/media_filter"
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
  getter scan_base_paths : Array(String)

  @lock : Mutex
  @read_lock = Mutex.new
  @registered_paths : Hash(String, String)?
  @directory_files : Hash(String, Array(String))?
  @directory_children : Hash(String, Array(String))?
  @binary_paths = Set(String).new
  getter? scan_files_active : Bool = false

  # Standalone parsers and analyzers also accept explicit files. In the scan
  # pipeline, every resolved source path must come from this registry.
  def with_scan_files(&)
    previous = @scan_files_active
    @scan_files_active = true
    yield
  ensure
    @scan_files_active = previous || false
  end

  def initialize
    @logger = NoirLogger.new(false, false, true, false)

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
  private FILE_MAP    = "file_map"
  private MEDIA_FILES = "media_files"

  # Register a path with no content — the detector's content-free fast path,
  # for files nothing will read during detection or passive scan.
  #
  # Invalidates the four derived views but deliberately NOT `@file_contents`.
  # A newly registered path has no cached content to invalidate, and dropping
  # the cache here would throw away every file read so far. `content_for`
  # returning nil for a registered path is valid: `read_source` loads
  # those files on demand, including files beyond the cache budget.
  def register_path(path : String)
    @a_map[FILE_MAP] ||= Array(String).new
    @a_map[FILE_MAP] << path
    invalidate_file_views
  end

  # Every registered path, in registration order.
  def all_files : Array(String)
    @a_map[FILE_MAP]? || Array(String).new
  end

  # A media file the walk reached but kept out of `file_map` (the media
  # filter). Nothing reads it for routes; a static mount still serves it.
  def register_media_path(path : String)
    (@a_map[MEDIA_FILES] ||= Array(String).new) << path
  end

  def media_files : Array(String)
    @a_map[MEDIA_FILES]? || Array(String).new
  end

  # Forget every registered file, its cached content, and every derived view.
  def reset_files
    @a_map.delete(FILE_MAP)
    @a_map.delete(MEDIA_FILES)
    @file_contents.clear
    @content_cache_used = 0_i64
    @content_cache_skipped = 0
    @binary_paths.clear
    invalidate_file_views
  end

  # The memoised views are rebuilt on next read; the indexes sit behind a
  # `_built` flag, so a lookup taken before a later registration would
  # otherwise keep serving the older file list.
  private def invalidate_file_views
    @expanded_file_map = nil
    @expanded_path_index = nil
    @registered_paths = nil
    @directory_files = nil
    @directory_children = nil
    @extension_index_built = false
    @basename_index_built = false
  end

  # One-shot used by the detector's file reader: push the path into
  # `file_map` and (budget permitting) cache the content so analyzers
  # can skip the second `File.read`. Files whose content exceeds the
  # remaining budget are still registered in `file_map` but not cached,
  # and `read_source` can still load them on demand.
  def register_file(path : String, content : String)
    register_path(path)

    cache_content(path, content)
  end

  private def cache_content(path : String, content : String)
    return if @content_cache_budget <= 0
    return if @file_contents.has_key?(path)
    size = content.bytesize.to_i64
    if size > @content_cache_budget - @content_cache_used
      @content_cache_skipped += 1
      return
    end
    @file_contents[path] = content
    @content_cache_used += size
  end

  # Returns cached content without opening the file.
  def content_for(path : String) : String?
    @file_contents[path]?
  end

  # Resolve an import or other derived path back to its spelling in the scan.
  def source_path?(path : String) : String?
    paths = @registered_paths
    unless paths
      pairs = expanded_file_map
      paths = @lock.synchronize do
        @registered_paths ||= pairs.each_with_object({} of String => String) do |(original, expanded), index|
          index[expanded] ||= original
        end
      end
    end
    paths[expanded_path_for(path)]?
  end

  # Use the scan directory index when resolving optional files. Standalone
  # callers still resolve paths in the directory they were given.
  def source_file?(path : String) : Bool
    @scan_files_active ? !source_path?(path).nil? : File.file?(path)
  end

  # The text read boundary for analyzers and report enrichment. A cache miss
  # still uses the same membership and binary checks as a cache hit.
  def read_source(path : String) : String?
    if @scan_files_active
      path = source_path?(path) || return
    else
      return if MediaFilter.media_file?(path)
    end

    @read_lock.synchronize do
      if cached = content_for(path)
        return cached
      end
      return if @binary_paths.includes?(path)

      if @scan_files_active
        info = File.info(path, follow_symlinks: false)
        return unless info.file?
        return if MediaFilter.skip_check(path, info: info, sniff_binary: false)
      end
      content = Noir::TextFile.read(path, info)
      if content.to_slice.includes?(0_u8)
        @binary_paths << path if @scan_files_active
        return
      end
      cache_content(path, content) if @scan_files_active
      content
    end
  end

  # Files under a root in walk order. Use an extension when the caller
  # already knows the kind of source it needs.
  def source_files_under(root : String, extension : String? = nil) : Array(String)
    files = extension ? files_by_extension(extension) : all_files
    return files.dup if root.empty?

    normalized = Noir::PathScope.normalize_root(root)
    files.select { |file| Noir::PathScope.under_normalized_root?(expanded_path_for(file), normalized) }
  end

  # Public assets need paths even when the text reader excludes their bytes.
  def static_files_under(root : String) : Array(String)
    normalized = Noir::PathScope.normalize_root(root)
    media = media_files.select { |path| Noir::PathScope.under_normalized_root?(Noir::PathScope.expand(path), normalized) }
    source_files_under(root) + media
  end

  def source_files_in(dir : String) : Array(String)
    source_directories[0][Noir::PathScope.normalize_root(dir)]? || [] of String
  end

  def source_child_directories(dir : String) : Array(String)
    source_directories[1][Noir::PathScope.normalize_root(dir)]? || [] of String
  end

  def source_directory?(dir : String) : Bool
    files, children = source_directories
    normalized = Noir::PathScope.normalize_root(dir)
    files.has_key?(normalized) || children.has_key?(normalized)
  end

  private def source_directories : {Hash(String, Array(String)), Hash(String, Array(String))}
    if (files = @directory_files) && (children = @directory_children)
      return {files, children}
    end

    pairs = expanded_file_map
    @lock.synchronize do
      if (files = @directory_files) && (children = @directory_children)
        return {files, children}
      end

      files = Hash(String, Array(String)).new
      children = Hash(String, Array(String)).new
      seen = Set(String).new
      pairs.each do |original, expanded|
        dir = File.dirname(expanded)
        (files[dir] ||= [] of String) << original
        while seen.add?(dir)
          parent = File.dirname(dir)
          break if parent == dir
          (children[parent] ||= [] of String) << dir
          dir = parent
        end
      end
      @directory_files = files
      @directory_children = children
      {files, children}
    end
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
      built = files ? files.map { |file| {file, Noir::PathScope.expand(file)} } : [] of Tuple(String, String)
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
    expanded_path_index[path]? || Noir::PathScope.expand(path)
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
      # `LOGIN.ASP` is indexed as `.asp`; see `Noir::FileExtension`.
      @extension_index_built = rebuild_path_index(@extension_index) { |file| Noir::FileExtension.index_key(File.extname(file)) }
    end
  end

  # Get files by extension using the index (O(1) lookup)
  def files_by_extension(extension : String) : Array(String)
    build_extension_index
    @extension_index[Noir::FileExtension.index_key(extension)]? || Array(String).new
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
    @basename_index.clear
    reset_files
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
