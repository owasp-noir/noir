require "./logger"
require "./code_block"
require "./endpoint"

class Analyzer
  @result : Array(Endpoint)
  @endpoint_references : Array(EndpointReference)
  @base_path : String
  @url : String
  @scope : String
  @logger : NoirLogger
  @is_debug : Bool
  @is_color : Bool
  @is_log : Bool

  def initialize(options : Hash(Symbol, String))
    @base_path = options[:base]
    @url = options[:url]
    @result = [] of Endpoint
    @endpoint_references = [] of EndpointReference
    @scope = options[:scope]
    @is_debug = str_to_bool(options[:debug])
    @is_color = str_to_bool(options[:color])
    @is_log = str_to_bool(options[:nolog])

    @logger = NoirLogger.new @is_debug, @is_color, @is_log
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

  define_getter_methods [result, base_path, url, scope, logger]
end

class FileAnalyzer < Analyzer
  @@hooks = [] of Proc(String, String, Nil)

  def hooks_count
    @@hooks.size
  end

  def self.add_hook(func : Proc(String, String, Nil))
    @@hooks << func
  end

  def analyze
    begin
      Dir.glob("#{base_path}/**/*") do |path|
        next if File.directory?(path)
        relative_path = get_relative_path(base_path, path)
        hooks.each do |hook|
          hook.call(relative_path, @url)
        end
      end
    rescue e
      logger.debug e
    end

    @result
  end
end
