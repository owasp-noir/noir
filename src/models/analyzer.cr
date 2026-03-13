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

  def parallel_analyze(channel : Channel(String), &block : String -> Nil)
    WaitGroup.wait do |wg|
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
    populate_channel_with_files(channel)

    WaitGroup.wait do |wg|
      @options["concurrency"].to_s.to_i.times do
        wg.spawn do
          loop do
            begin
              path = channel.receive?
              break if path.nil?
              next if File.directory?(path)

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
end
