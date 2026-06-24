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

  # Split a URL into lowercased, separator-delimited segments. Shared by the
  # path-keyword taggers. Taggers needing scheme-stripping or other tweaks
  # (e.g. debug) override this locally.
  private def url_parts(url : String) : Array(String)
    url.downcase.split(/[\/\-_\.]+/).reject(&.empty?)
  end

  # Canonical parameter-name normalization (lowercase, hyphen -> underscore).
  # Taggers with bespoke normalization (admin's strip-all, pii's camelCase
  # splitter) override this locally.
  private def normalize_param_name(name : String) : String
    name.downcase.tr("-", "_")
  end
end
