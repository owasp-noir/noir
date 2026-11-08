require "yaml"
require "../models/tagger"
require "../models/endpoint"
require "../utils/http_symbols"

# Taggers defined as data: one YAML file per tagger under
# `src/tagger/rules/`, embedded at compile time. A rule joins the same
# registry as the `Noir::TaggerFor` classes (`-T` key, `noir list taggers`,
# run order), so to users there is no difference between the two kinds.
#
# The format is documented in `src/tagger/rules/README.md`. Anything the
# vocabulary below can't express stays a Crystal tagger.
module NoirTagRules
  class RuleError < Exception
  end

  alias Matcher = Proc(Endpoint, Bool)

  record Rule,
    key : String,
    name : String,
    summary : String,
    order : Int32,
    tag_name : String,
    tag_tagger : String,
    tag_description : String,
    matcher : Matcher,
    match_examples : Array(Endpoint),
    no_match_examples : Array(Endpoint),
    source : String

  # One `param:` condition. A param passes when it satisfies every filter
  # that is set; `name` and `name_prefix` together mean "either".
  record ParamFilter,
    names : Set(String)?,
    prefixes : Array(String)?,
    types : Set(String)?,
    values : Array(String)? do
    def match?(param : Param) : Bool
      if t = types
        return false unless t.includes?(param.param_type.downcase)
      end
      if names || prefixes
        n = NoirTagRules.normalize_name(param.name)
        return false unless names.try(&.includes?(n)) || prefixes.try(&.any? { |pre| n.starts_with?(pre) })
      end
      if v = values
        lowered = param.value.downcase
        return false unless v.any? { |s| lowered.includes?(s) }
      end
      true
    end
  end

  RULE_KEYS    = %w[key name summary order tag match examples]
  TAG_KEYS     = %w[name tagger description]
  PARAM_KEYS   = %w[name name_prefix type value_contains min]
  EXAMPLE_KEYS = %w[method url protocol params]
  SEGMENT_SEP  = /[\/\-_.]/

  # `is_admin`, `isAdmin` and `is-admin` are one key.
  def self.normalize_name(name : String) : String
    name.downcase.gsub(/[-_]/, "")
  end

  # Same split as `Tagger#url_parts`.
  def self.url_parts(url : String) : Array(String)
    url.downcase.split(/[\/\-_\.]+/).reject(&.empty?)
  end

  BUILTIN_SOURCES = {{ run("./rules/embed.cr", __DIR__ + "/rules") }}

  BUILTIN = BUILTIN_SOURCES.map { |file, content| parse(content, file) }

  def self.find(key : String) : Rule?
    BUILTIN.find { |rule| rule.key == key }
  end

  def self.parse(content : String, source : String) : Rule
    doc = YAML.parse(content).as_h? || raise RuleError.new("#{source}: a rule file must be a mapping")
    h = string_keys(doc, RULE_KEYS, source)

    tag = string_keys(h["tag"]?.try(&.as_h?) || raise(RuleError.new("#{source}: 'tag' must be a mapping")), TAG_KEYS, "#{source} tag")
    key = required_string(h, "key", source)
    raise RuleError.new("#{source}: key '#{key}' must match [a-z0-9_]+") unless key.matches?(/\A[a-z0-9_]+\z/)
    order = h["order"]?.try(&.as_i?) || raise RuleError.new("#{source}: 'order' must be an integer")
    match = h["match"]? || raise RuleError.new("#{source}: 'match' is required")

    examples = h["examples"]?.try { |e| string_keys(e.as_h? || raise(RuleError.new("#{source}: 'examples' must be a mapping")), %w[match no_match], "#{source} examples") }

    Rule.new(
      key: key,
      name: required_string(h, "name", source),
      summary: required_string(h, "summary", source),
      order: order,
      tag_name: tag["name"]?.try(&.as_s?) || key,
      tag_tagger: required_string(tag, "tagger", "#{source} tag"),
      tag_description: required_string(tag, "description", "#{source} tag"),
      matcher: compile(match, source),
      match_examples: parse_examples(examples.try(&.["match"]?), source),
      no_match_examples: parse_examples(examples.try(&.["no_match"]?), source),
      source: source,
    )
  end

  # A mapping with several keys means all of them.
  def self.compile(node : YAML::Any, where : String) : Matcher
    h = node.as_h? || raise RuleError.new("#{where}: a condition must be a mapping, got #{node.inspect}")
    raise RuleError.new("#{where}: empty condition") if h.empty?
    matchers = h.map do |k, v|
      compile_key(k.as_s? || raise(RuleError.new("#{where}: condition keys must be strings")), v, where)
    end
    return matchers[0] if matchers.size == 1
    ->(ep : Endpoint) { matchers.all?(&.call(ep)) }
  end

  private def self.compile_key(key : String, value : YAML::Any, where : String) : Matcher
    case key
    when "any", "all"
      list = value.as_a? || raise RuleError.new("#{where}: '#{key}' takes a list of conditions")
      raise RuleError.new("#{where}: '#{key}' is empty") if list.empty?
      subs = list.map { |c| compile(c, where) }
      key == "any" ? ->(ep : Endpoint) { subs.any?(&.call(ep)) } : ->(ep : Endpoint) { subs.all?(&.call(ep)) }
    when "path_segment"
      words = strings(value, key, where).map(&.downcase).to_set
      if bad = words.find(&.matches?(SEGMENT_SEP))
        raise RuleError.new("#{where}: path_segment '#{bad}' contains a separator (/ - _ .) and can never match a single segment")
      end
      ->(ep : Endpoint) { url_parts(ep.url).any? { |part| words.includes?(part) } }
    when "url_contains"
      needles = strings(value, key, where).map(&.downcase)
      ->(ep : Endpoint) { url = ep.url.downcase; needles.any? { |s| url.includes?(s) } }
    when "method", "method_not"
      methods = strings(value, key, where).flat_map { |m| m.downcase == "safe" ? SAFE_HTTP_METHODS.to_a : [m.upcase] }.to_set
      negate = key == "method_not"
      ->(ep : Endpoint) { methods.includes?(ep.method.upcase) != negate }
    when "protocol"
      protocols = strings(value, key, where).map(&.downcase).to_set
      ->(ep : Endpoint) { protocols.includes?(ep.protocol.downcase) }
    when "param"
      compile_param(value, where)
    else
      raise RuleError.new("#{where}: unknown condition '#{key}'")
    end
  end

  private def self.compile_param(value : YAML::Any, where : String) : Matcher
    h = string_keys(value.as_h? || raise(RuleError.new("#{where}: 'param' takes a mapping")), PARAM_KEYS, "#{where} param")
    raise RuleError.new("#{where}: 'param' needs at least one filter") if h.reject("min").empty?
    min = h["min"]?.try { |m| m.as_i? || raise RuleError.new("#{where}: param 'min' must be an integer") } || 1
    raise RuleError.new("#{where}: param 'min' must be >= 1") if min < 1

    filter = ParamFilter.new(
      names: h["name"]?.try { |v| strings(v, "name", where).map { |s| normalize_name(s) }.to_set },
      prefixes: h["name_prefix"]?.try { |v| strings(v, "name_prefix", where).map { |s| normalize_name(s) } },
      types: h["type"]?.try { |v| strings(v, "type", where).map(&.downcase).to_set },
      values: h["value_contains"]?.try { |v| strings(v, "value_contains", where).map(&.downcase) },
    )
    ->(ep : Endpoint) { ep.params.count { |p| filter.match?(p) } >= min }
  end

  private def self.parse_examples(node : YAML::Any?, source : String) : Array(Endpoint)
    return [] of Endpoint unless node
    list = node.as_a? || raise RuleError.new("#{source}: examples must be lists")
    list.map do |ex|
      h = string_keys(ex.as_h? || raise(RuleError.new("#{source}: an example must be a mapping")), EXAMPLE_KEYS, "#{source} example")
      params = (h["params"]?.try(&.as_a?) || [] of YAML::Any).map do |p|
        ph = string_keys(p.as_h? || raise(RuleError.new("#{source}: an example param must be a mapping")), %w[name value type], "#{source} example param")
        Param.new(required_string(ph, "name", "#{source} example param"), ph["value"]?.to_s, ph["type"]?.try(&.as_s?) || "query")
      end
      endpoint = Endpoint.new(required_string(h, "url", "#{source} example"), h["method"]?.try(&.as_s?) || "GET", params)
      h["protocol"]?.try(&.as_s?).try { |proto| endpoint.protocol = proto }
      endpoint
    end
  end

  # Re-keys a YAML mapping by string and rejects keys outside `allowed`,
  # so a typo fails the load instead of silently doing nothing.
  private def self.string_keys(h : Hash(YAML::Any, YAML::Any), allowed : Array(String), where : String) : Hash(String, YAML::Any)
    h.each_with_object({} of String => YAML::Any) do |(k, v), acc|
      key = k.as_s? || raise RuleError.new("#{where}: keys must be strings")
      raise RuleError.new("#{where}: unknown key '#{key}' (allowed: #{allowed.join(", ")})") unless allowed.includes?(key)
      acc[key] = v
    end
  end

  private def self.required_string(h : Hash(String, YAML::Any), key : String, where : String) : String
    value = h[key]?.try(&.as_s?)
    raise RuleError.new("#{where}: '#{key}' is required and must be a string") if value.nil? || value.blank?
    value
  end

  private def self.strings(value : YAML::Any, key : String, where : String) : Array(String)
    list = value.as_a?.try(&.map { |v| v.as_s? || v.raw.to_s }) || value.as_s?.try { |s| [s] }
    raise RuleError.new("#{where}: '#{key}' takes a string or a list of strings") if list.nil? || list.empty?
    list
  end
end

# The `Tagger` that runs one `NoirTagRules::Rule`. It carries no
# `Noir::TaggerFor` annotation on purpose: `NoirTaggers` registers each rule
# by its own key, not this class.
class RuleTagger < Tagger
  def initialize(options : Hash(String, YAML::Any), @rule : NoirTagRules::Rule)
    super(options)
    @name = @rule.key
  end

  protected def check_endpoint(endpoint : Endpoint)
    return unless @rule.matcher.call(endpoint)
    endpoint.add_tag(Tag.new(@rule.tag_name, @rule.tag_description, @rule.tag_tagger))
  end
end
