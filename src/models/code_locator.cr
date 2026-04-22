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
  @file_usage_stats : Hash(String, Int32) # Track number of file reads
  @extension_index : Hash(String, Array(String))
  @extension_index_built : Bool
  @file_contents : Hash(String, String)
  @content_cache_budget : Int64
  @content_cache_used : Int64
  @content_cache_skipped : Int32

  def initialize
    options = {"debug" => "false", "verbose" => "false", "color" => "true", "nolog" => "false"}
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log

    @s_map = Hash(String, String).new
    @a_map = Hash(String, Array(String)).new
    @file_usage_stats = Hash(String, Int32).new
    @extension_index = Hash(String, Array(String)).new
    @extension_index_built = false

    @file_contents = Hash(String, String).new
    @content_cache_budget = resolve_content_cache_budget
    @content_cache_used = 0_i64
    @content_cache_skipped = 0
  end

  private def resolve_content_cache_budget : Int64
    return 0_i64 if ENV["NOIR_CONTENT_CACHE_DISABLE"]?.to_s.downcase.in?({"true", "1", "yes"})
    if raw = ENV["NOIR_CONTENT_CACHE_MAX_MB"]?
      parsed = raw.to_i64?
      return parsed * 1024 * 1024 if parsed && parsed >= 0
    end
    DEFAULT_CONTENT_CACHE_BUDGET
  end

  def self.instance : CodeLocator
    @@instance ||= new
  end

  def set(key : String, value : String)
    @s_map[key] = value
  end

  def get(key : String) : (String | Array(String))
    @s_map[key]
  rescue
    ""
  end

  def push(key : String, value : String)
    @a_map[key] ||= Array(String).new
    @a_map[key] << value

    # Track file usage if this is the file_map
    if key == "file_map"
      increment_file_usage(value)
    end
  end

  # One-shot used by the detector's file reader: push the path into
  # `file_map` and (budget permitting) cache the content so analyzers
  # can skip the second `File.read`. Files whose content exceeds the
  # remaining budget are still registered in `file_map` but not cached,
  # and `content_for(path)` returns `nil` for them — callers must keep
  # a `File.read` fallback.
  def register_file(path : String, content : String)
    push("file_map", path)

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

  def all(key : String) : Array(String)
    result = @a_map[key]?
    return result if result
    Array(String).new
  end

  # Build extension index from file_map for fast lookups
  def build_extension_index
    return if @extension_index_built
    @extension_index.clear
    files = @a_map["file_map"]?
    return unless files
    files.each do |file|
      ext = File.extname(file)
      @extension_index[ext] ||= Array(String).new
      @extension_index[ext] << file
    end
    @extension_index_built = true
  end

  # Get files by extension using the index (O(1) lookup)
  def files_by_extension(extension : String) : Array(String)
    build_extension_index
    @extension_index[extension]? || Array(String).new
  end

  def clear(key : String)
    @s_map.delete(key)
    @a_map.delete(key)
    if key == "file_map"
      @extension_index.clear
      @extension_index_built = false
      @file_contents.clear
      @content_cache_used = 0_i64
      @content_cache_skipped = 0
    end
  end

  def clear_all
    @s_map.clear
    @a_map.clear
    @file_usage_stats.clear
    @extension_index.clear
    @extension_index_built = false
    @file_contents.clear
    @content_cache_used = 0_i64
    @content_cache_skipped = 0
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

  # Get file usage statistics
  def file_usage_stats : Hash(String, Int32)
    @file_usage_stats
  end

  # Increment file usage count
  private def increment_file_usage(file_path : String)
    @file_usage_stats[file_path] ||= 0
    @file_usage_stats[file_path] += 1
  end

  # Show file usage statistics
  def show_file_stats
    @logger.sub("File Usage Statistics:")
    @logger.sub("  Total unique files: #{@file_usage_stats.size}")
    total_usages = @file_usage_stats.values.sum
    @logger.sub("  Total file reads: #{total_usages}")

    if @is_verbose && !@file_usage_stats.empty?
      @logger.sub("  Top 10 most accessed files:")
      @file_usage_stats.to_a.sort_by { |_, count| -count }[0..9].each do |file, count|
        @logger.sub("    #{count} times: #{file}")
      end
    end
  end
end
