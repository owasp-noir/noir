require "./logger"
require "./endpoint"
require "./file_helper"
require "../utils/wait_group"

class Analyzer
  include FileHelper

  @result : Array(Endpoint)
  @endpoint_references : Array(EndpointReference)
  @base_path : String
  @url : String
  @logger : NoirLogger
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @options : Hash(String, YAML::Any)

  def initialize(options : Hash(String, YAML::Any))
    @base_path = options["base"].to_s
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

  macro define_getter_methods(names)
    {% for name, index in names %}
      def {{name.id}}
        @{{name.id}}
      end
    {% end %}
  end

  define_getter_methods [result, base_path, url, logger]
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
    channel = Channel(String).new
    populate_channel_with_files(channel)

    WaitGroup.wait do |wg|
      @options["concurrency"].to_s.to_i.times do
        wg.spawn do
          loop do
            begin
              path = channel.receive?
              break if path.nil?
              next if File.directory?(path)
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
