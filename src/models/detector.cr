require "./logger"
require "../utils/utils"
require "yaml"

class Detector
  @logger : NoirLogger
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @name : String
  @base_path : String
  @base_paths : Array(String)

  def initialize(options : Hash(String, YAML::Any))
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @name = ""
    @base_paths = options["base"].as_a.map(&.to_s)
    @base_path = @base_paths.first? || ""

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log
  end

  def detect(filename : String, file_contents : String) : Bool
    # After inheriting the class, write an action code here.
    false
  end

  macro define_getter_methods(names)
    {% for name, index in names %}
      def {{name.id}}
        @{{name.id}}
      end
    {% end %}
  end

  define_getter_methods [name, logger]
end
