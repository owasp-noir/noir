require "json"
require "yaml"

struct Endpoint
  include JSON::Serializable
  include YAML::Serializable
  property url, method, params, protocol, kind, details, tags, callees, internal
  property ai_context : AIContext?

  # Non-HTTP mobile deep-link protocols. These endpoints are app URLs you
  # open (myapp://, intent://, verified https app links) or ContentResolver
  # surfaces you address (content://authority), not HTTP requests you send —
  # so they are excluded from HTTP-shaped output (curl/httpie/powershell,
  # OpenAPI) and from active probing / proxy delivery.
  MOBILE_PROTOCOLS = Set{"mobile-scheme", "android-intent", "universal-link", "android-provider"}

  def mobile? : Bool
    MOBILE_PROTOCOLS.includes?(@protocol)
  end

  # Non-HTTP command-line entry points. A CLI endpoint models the
  # invocation surface of a command-line program: a (sub)command addressed
  # as `cli://<binary>/<subcommand>` whose inputs are flags/options
  # (param_type "flag"), positional arguments ("argument"), and consumed
  # environment variables ("env"). The method is the synthetic verb "CLI".
  # Like mobile endpoints these are not HTTP requests, so they are excluded
  # from HTTP-shaped output (curl/httpie/powershell, OpenAPI, Postman) and
  # from active probing / proxy delivery, and the optimizer keeps their URL
  # verbatim instead of normalizing it as an HTTP path.
  CLI_PROTOCOLS = Set{"cli"}

  def cli? : Bool
    CLI_PROTOCOLS.includes?(@protocol)
  end

  # True for endpoints whose URL is not an HTTP path and must be preserved
  # verbatim — mobile deep-link schemes and CLI command surfaces. The
  # optimizer skips URL normalization for these, and the HTTP output
  # builders / active deliverers skip them entirely.
  def non_http? : Bool
    mobile? || cli?
  end

  # Free-form metadata for non-HTTP entry points (mobile deep-link
  # schemes, Android intents, universal links: action/category/host/
  # package/...). nil for ordinary endpoints and suppressed from
  # serialization so the JSON/YAML schema is unchanged for them.
  @[JSON::Field(ignore_serialize: metadata.nil?)]
  @[YAML::Field(ignore_serialize: metadata.nil?)]
  property metadata : Hash(String, String)?

  # Per-endpoint context for AI code reviewers: 1-hop callees from the
  # handler body. Best-effort, intentionally incomplete on dynamic
  # dispatch / middleware / decorators. Populated by analyzers that
  # opt in; empty for the rest.
  @callees : Array(Callee) = [] of Callee

  def initialize(@url : String, @method : String, params : Array(Param) = [] of Param,
                 details : Details = Details.new, @internal : Bool = false)
    @params = params.map(&.detached_copy)
    @details = details.detached_copy
    @protocol = "http"
    @kind = ""
    @tags = [] of Tag
    @callees = [] of Callee
    @ai_context = nil
    @metadata = nil
  end

  def initialize(@url : String, @method : String, details : Details)
    @params = [] of Param
    @details = details.detached_copy
    @protocol = "http"
    @kind = ""
    @tags = [] of Tag
    @callees = [] of Callee
    @internal = false
    @ai_context = nil
    @metadata = nil
  end

  def details=(details : Details)
    @details = details.detached_copy
  end

  def protocol=(protocol : String)
    @protocol = protocol
  end

  def internal=(internal : Bool)
    @internal = internal
  end

  # Dedup by (name, tagger) like push_callee/push_param do for their
  # collections, so re-tagging the same target (e.g. a match in two
  # code_paths) can't surface a duplicate "auth auth" in the text output.
  def add_tag(tag : Tag)
    return if @tags.any? { |existing| existing.name == tag.name && existing.tagger == tag.tagger }
    @tags << tag
  end

  # Dedup by (name, param_type) like push_callee/add_tag do for their
  # collections. A handler that reads the same input twice
  # (`params[:id]` on two lines, a path param re-read in the body) used
  # to surface the identical Param multiple times in the raw `params`
  # list and the text output. `params_to_hash`/`==` already collapse on
  # name+type, so deduping here only trims redundant entries.
  def push_param(param : Param)
    return if @params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
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
    # Seed the six canonical buckets so consumers (mermaid, ==, etc.)
    # can read `params_hash["query"]` without a `has_key?` guard.
    # Auto-create any additional bucket on insert so a stray Param with
    # an unconventional `param_type` (e.g. "websocket", framework-
    # specific shapes) doesn't raise KeyError on write.
    params_hash = {} of String => Hash(String, String)
    %w[query json form header cookie path].each do |type|
      params_hash[type] = {} of String => String
    end

    @params.each do |param|
      type = param.param_type
      params_hash[type] = {} of String => String unless params_hash.has_key?(type)
      params_hash[type][param.name] = param.value
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

  # Dedup by (name, tagger) like push_callee/push_param do for their
  # collections, so re-tagging the same target (e.g. a match in two
  # code_paths) can't surface a duplicate "auth auth" in the text output.
  def add_tag(tag : Tag)
    return if @tags.any? { |existing| existing.name == tag.name && existing.tagger == tag.tagger }
    @tags << tag
  end

  def detached_copy : Param
    copy = Param.new(@name, @value, @param_type)
    @tags.each { |tag| copy.add_tag(tag) }
    copy
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

  def detached_copy : Details
    copy = Details.new
    @code_paths.each { |code_path| copy.add_path(code_path) }
    if status_code = @status_code
      copy.status_code = status_code
    end
    if technology = @technology
      copy.technology = technology
    end
    copy
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

struct AIContext
  include JSON::Serializable
  include YAML::Serializable

  MAX_PER_SECTION = 16

  property guards : Array(AIContextEntry) = [] of AIContextEntry
  property callees : Array(AIContextEntry) = [] of AIContextEntry
  property sources : Array(AIContextEntry) = [] of AIContextEntry
  property sinks : Array(AIContextEntry) = [] of AIContextEntry
  property validators : Array(AIContextEntry) = [] of AIContextEntry
  property signals : Array(AIContextEntry) = [] of AIContextEntry

  def initialize
    @guards = [] of AIContextEntry
    @callees = [] of AIContextEntry
    @sources = [] of AIContextEntry
    @sinks = [] of AIContextEntry
    @validators = [] of AIContextEntry
    @signals = [] of AIContextEntry
  end

  def empty? : Bool
    @guards.empty? &&
      @callees.empty? &&
      @sources.empty? &&
      @sinks.empty? &&
      @validators.empty? &&
      @signals.empty?
  end

  def push_guard(entry : AIContextEntry)
    push_entry(@guards, entry)
  end

  def push_callee(entry : AIContextEntry)
    push_entry(@callees, entry)
  end

  def push_source(entry : AIContextEntry)
    push_entry(@sources, entry)
  end

  def push_sink(entry : AIContextEntry)
    push_entry(@sinks, entry)
  end

  def push_validator(entry : AIContextEntry)
    push_entry(@validators, entry)
  end

  def push_signal(entry : AIContextEntry)
    push_entry(@signals, entry)
  end

  private def push_entry(bucket : Array(AIContextEntry), entry : AIContextEntry)
    return if bucket.size >= MAX_PER_SECTION
    return if bucket.any? { |existing| existing == entry }
    bucket << entry
  end
end

struct AIContextEntry
  include JSON::Serializable
  include YAML::Serializable

  property kind, name, source, description, path, line, confidence, snippet

  def initialize(@kind : String,
                 @name : String,
                 @source : String? = nil,
                 @description : String? = nil,
                 @path : String? = nil,
                 @line : Int32? = nil,
                 @confidence : Int32? = nil,
                 @snippet : String? = nil)
  end

  def ==(other : AIContextEntry) : Bool
    @kind == other.kind &&
      @name == other.name &&
      @source == other.source &&
      @path == other.path &&
      @line == other.line
  end
end
