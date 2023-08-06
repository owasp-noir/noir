require "./logger"

class Detector
  @logger : NoirLogger
  @is_debug : Bool
  @is_color : Bool
  @is_log : Bool
  @name : String

  def initialize(options : Hash(Symbol, String))
    @is_debug = str_to_bool(options[:debug])
    @is_color = str_to_bool(options[:color])
    @is_log = str_to_bool(options[:nolog])
    @name = ""

    @logger = NoirLogger.new @is_debug, @is_color, @is_log
  end

  def detect(filename : String, file_contents : String) : Bool
    # After inheriting the class, write an action code here.
    false
  end

  def name
    @name
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
