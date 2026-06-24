require "./logger"
require "./endpoint"
require "./file_helper"
require "wait_group"
require "../utils/media_filter"
require "../utils/path_scope"
require "../utils/utils"

class Analyzer
  include FileHelper

  DEFAULT_CHANNEL_CAPACITY         = 128
  DEFAULT_CONTENT_CHANNEL_CAPACITY =  16
  MAX_ANALYZER_WORKERS             =  64

  @result : Array(Endpoint)
  @endpoint_references : Array(EndpointReference)
  @base_path : String
  @base_paths : Array(String)
  @normalized_base_paths : Array(Tuple(String, String))
  @url : String
  @logger : NoirLogger
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @options : Hash(String, YAML::Any)
  # path => longest-matching configured base. Populated lazily by
  # `configured_base_for`; only used on multi-base (monorepo) scans.
  @configured_base_cache = {} of String => String
  @configured_base_cache_mutex = Mutex.new

  def initialize(options : Hash(String, YAML::Any))
    @base_paths = options["base"].as_a.map(&.to_s)
    @base_path = @base_paths.first? || ""
    @normalized_base_paths = @base_paths.map { |base| {base, Noir::PathScope.normalize_root(base)} }
    @url = options["url"].to_s
    @result = [] of Endpoint
    @endpoint_references = [] of EndpointReference
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @options = options

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log
  end

  def analyze
    # After inheriting the class, write an action code here.
  end

  # Prefer the detector-populated cache over a fresh disk read. On
  # cache miss (budget exhausted, cache cleared between runs, path
  # not registered via register_file) falls back to `File.read`.
  #
  # Analyzers migrating from direct `File.read(path, ...)` calls
  # should use this helper so the second read of files the detector
  # already loaded is free.
  def read_file_content(path : String) : String
    cached = CodeLocator.instance.content_for(path)
    return cached if cached
    File.read(path, encoding: "utf-8", invalid: :skip)
  end

  # Callees feed `--include-callee` (direct output) and `--ai-context`
  # (aggregated review context). Analyzers should consult this before
  # running their callee extractor so the work is skipped on default
  # scans where neither flag is set.
  def callees_needed? : Bool
    any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
  end

  # Resolves the longest configured base that owns `path`. Cross-file
  # indexes key their roots off this, which scopes them per base. Note the
  # designed limitation: nested/overlapping base paths (e.g. `-b /repo
  # -b /repo/sub`) don't compose cross-base prefixes, because a definition
  # and its use can resolve to different longest-matching bases — sibling
  # layouts (the common monorepo shape) are the supported case.
  protected def configured_base_for(path : String) : String
    # Single configured base: the longest-match resolution can only ever
    # return that base (or the identical `@base_path` fallback), so skip the
    # per-path `File.expand_path` work entirely. This is the common case and
    # keeps single-base scans free of the multi-base resolution overhead.
    return @base_path if @base_paths.size <= 1

    @configured_base_cache_mutex.synchronize do
      if cached = @configured_base_cache[path]?
        cached
      else
        @configured_base_cache[path] = longest_configured_base(path) || @base_path
      end
    end
  end

  private def longest_configured_base(path : String) : String?
    expanded_path = CodeLocator.instance.expanded_path_for(path)
    best_base = nil.as(String?)
    best_size = -1

    @normalized_base_paths.each do |base, normalized|
      next unless Noir::PathScope.under_normalized_root?(expanded_path, normalized)
      next unless normalized.size > best_size

      best_base = base
      best_size = normalized.size
    end

    best_base
  end

  # Preferred overload: accepts a file list and creates both the
  # producer and worker fibers inside a single WaitGroup so every
  # fiber is tracked.  The bare-`spawn` producer in the channel-based
  # overload below was an orphan that could trigger "can't resume a
  # running fiber" under Crystal ≥1.20's M:N scheduler when multiple
  # analyzers ran concurrently.
  def parallel_analyze(files : Array(String), &block : String -> Nil)
    channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
    WaitGroup.wait do |wg|
      # Producer — tracked by the WaitGroup
      wg.spawn do
        files.each { |file| channel.send(file) }
        channel.close
      end

      worker_count = @options["concurrency"].to_s.to_i
      worker_count = MAX_ANALYZER_WORKERS if worker_count > MAX_ANALYZER_WORKERS
      worker_count = 1 if worker_count < 1
      worker_count.times do
        wg.spawn do
          loop do
            begin
              path = channel.receive?
              break if path.nil?
              block.call(path)
            rescue File::NotFoundError
              @logger.debug "File not found: #{path}"
            rescue e : Exception
              if path
                @logger.debug "Error processing file #{path}: #{e.message}"
              else
                @logger.debug "Error in worker: #{e.message}"
              end
            end
          end
        end
      end
    end
  end

  getter result, base_path, base_paths, url, logger
end

class FileAnalyzer < Analyzer
  @@hooks = [] of Proc(String, String, Array(Endpoint))

  def hooks_count
    @@hooks.size
  end

  def self.add_hook(func : Proc(String, String, Array(Endpoint)))
    @@hooks << func
  end

  def analyze
    channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

    WaitGroup.wait do |wg|
      # Producer — tracked by the WaitGroup
      wg.spawn do
        all_files.each { |file| channel.send(file) }
        channel.close
      end

      @options["concurrency"].to_s.to_i.times do
        wg.spawn do
          loop do
            begin
              path = channel.receive?
              break if path.nil?
              next if File.directory?(path)
              next if skip_file_analyzer?(path)

              logger.debug "Analyzing: #{path}"

              @@hooks.each do |hook|
                file_results = hook.call(path, @url)
                unless file_results.nil?
                  file_results.each do |file_result|
                    @result << file_result
                  end
                end
              end
            rescue e
              logger.debug e
            end
          end
        end
      end
    end

    @result
  end

  private def skip_file_analyzer?(path : String) : Bool
    har_files = CodeLocator.instance.all("har-path")
    har_files.is_a?(Array(String)) && har_files.includes?(path)
  end
end
