require "./logger"
require "./endpoint"
require "./file_helper"
require "wait_group"
require "../utils/media_filter"
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
  @url : String
  @logger : NoirLogger
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @options : Hash(String, YAML::Any)

  def initialize(options : Hash(String, YAML::Any))
    @base_paths = options["base"].as_a.map(&.to_s)
    @base_path = @base_paths.first? || ""
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

  macro define_getter_methods(names)
    {% for name, index in names %}
      def {{ name.id }}
        @{{ name.id }}
      end
    {% end %}
  end

  define_getter_methods [result, base_path, base_paths, url, logger]
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
                if !file_results.nil?
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
