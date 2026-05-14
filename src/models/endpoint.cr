require "json"
require "yaml"

struct Endpoint
  include JSON::Serializable
  include YAML::Serializable
  property url, method, params, protocol, details, tags, callees, internal

  # Per-endpoint context for AI code reviewers: 1-hop callees from the
  # handler body. Best-effort, intentionally incomplete on dynamic
  # dispatch / middleware / decorators. Populated by analyzers that
  # opt in; empty for the rest.
  @callees : Array(Callee) = [] of Callee

  def initialize(@url : String, @method : String, @params : Array(Param) = [] of Param,
                 @details : Details = Details.new, @internal : Bool = false)
    @protocol = "http"
    @tags = [] of Tag
    @callees = [] of Callee
  end

  def initialize(@url : String, @method : String, @details : Details)
    @params = [] of Param
    @protocol = "http"
    @tags = [] of Tag
    @callees = [] of Callee
    @internal = false
  end

  def details=(details : Details)
    @details = details
  end

  def protocol=(protocol : String)
    @protocol = protocol
  end

  def internal=(internal : Bool)
    @internal = internal
  end

  def add_tag(tag : Tag)
    @tags << tag
  end

  def push_param(param : Param)
    @params << param
  end

  # Add a callee, deduping by (name, path) and enforcing the
  # `Callee::MAX_PER_ENDPOINT` cap. Both checks are kept here so
  # individual analyzers can't forget them and let the list balloon.
  def push_callee(callee : Callee)
    return if @callees.size >= Callee::MAX_PER_ENDPOINT
    return if @callees.any? { |c| c.name == callee.name && c.path == callee.path }
    @callees << callee
  end

  def params_to_hash
    params_hash = {} of String => Hash(String, String)
    params_hash["query"] = {} of String => String
    params_hash["json"] = {} of String => String
    params_hash["form"] = {} of String => String
    params_hash["header"] = {} of String => String
    params_hash["cookie"] = {} of String => String
    params_hash["path"] = {} of String => String

    @params.each do |param|
      params_hash[param.param_type][param.name] = param.value
    end

    params_hash
  end

  def ==(other : Endpoint) : Bool
    return false unless @url == other.url
    return false unless @method == other.method

    self_params = params_to_hash
    other_params = other.params_to_hash

    # Ensure both hashes have the same set of keys before comparing values
    common_keys = self_params.keys & other_params.keys
    return false unless common_keys.size == self_params.keys.size && common_keys.size == other_params.keys.size

    common_keys.each do |key|
      return false unless self_params[key] == other_params[key]
    end

    true
  end
end

struct Param
  include JSON::Serializable
  include YAML::Serializable
  property name, value, param_type, tags

  # param_type can be "query", "json", "form", "header", "cookie"

  def initialize(@name : String, @value : String, @param_type : String)
    @tags = [] of Tag
  end

  def ==(other : Param) : Bool
    @name == other.name && @value == other.value && @param_type == other.param_type
  end

  def param_type=(value : String)
    @param_type = value
  end

  def add_tag(tag : Tag)
    @tags << tag
  end
end

struct Details
  include JSON::Serializable
  include YAML::Serializable
  property code_paths : Array(PathInfo) = [] of PathInfo
  property status_code : Int32?
  property technology : String?

  # New details types can be added in the future.

  def initialize(code_path : PathInfo? = nil)
    @code_paths << code_path if code_path
  end

  def add_path(code_path : PathInfo)
    @code_paths << code_path
  end

  def status_code=(status_code : Int32)
    @status_code = status_code
  end

  def ==(other : Details) : Bool
    return false if @status_code != other.status_code
    return false if @technology != other.technology
    return false if @code_paths.size != other.code_paths.size
    return false unless @code_paths.all? { |path| other.code_paths.any? { |other_path| path == other_path } }
    true
  end
end

struct PathInfo
  include JSON::Serializable
  include YAML::Serializable
  property path, line

  def initialize(@path : String)
    @line = nil
  end

  def initialize(@path : String, @line : Int32?)
  end

  def ==(other : PathInfo) : Bool
    @path == other.path && @line == other.line
  end
end

struct EndpointReference
  include JSON::Serializable
  property endpoint, metadata

  def initialize(@endpoint : Endpoint, @metadata : Hash(Symbol, String))
  end
end

struct Tag
  include JSON::Serializable
  include YAML::Serializable
  property name, description, tagger

  def initialize(@name : String, @description : String, @tagger : String)
  end
end

# A function/method invoked directly from an endpoint's handler body
# (1-hop only). `name` is the textual callee as it appears in source
# (e.g. `User.create`, `raw_sql_query`). `path` and `line` are
# best-effort location metadata: analyzers with definition resolution use
# the callee's definition when reachable; the rest keep the call site.
#
# The list is intentionally incomplete: dynamic dispatch (Rails
# `before_action`, JS middleware, Python decorators) bypasses the body
# walk by design. AI consumers should treat callees as a useful prior,
# not a complete dependency graph.
struct Callee
  include JSON::Serializable
  include YAML::Serializable
  property name, path, line

  MAX_PER_ENDPOINT = 10

  def initialize(@name : String, @path : String? = nil, @line : Int32? = nil)
  end

  def ==(other : Callee) : Bool
    @name == other.name && @path == other.path && @line == other.line
  end
end
