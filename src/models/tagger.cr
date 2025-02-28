require "./logger"

class Tagger
  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @name : String

  def initialize(options : Hash(String, YAML::Any))
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @options = options
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @name = ""

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log
  end

  def name
    @name
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # After inheriting the class, write an action code here.

    endpoints
  end
end
