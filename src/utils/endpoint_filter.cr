require "../models/endpoint"
require "./http_symbols"

# The endpoint matcher behind `noir query`'s filters, and behind
# `noir scan --only-endpoints / --exclude-endpoints`, which spell the same
# filters as `key:value` terms. One matcher, so a pattern means the same
# thing in both places.
module Noir::EndpointFilter
  # Guards that gate *who* may call the route. Rate limiting and CSRF checks
  # are guards the augmentor records, but neither stops an anonymous caller,
  # and "no auth" is what `--no-guard` asks.
  NON_AUTH_GUARD_KINDS = {"rate_limit_guard", "csrf_guard"}

  def self.auth_guards(context : AIContext?) : Array(AIContextEntry)
    return [] of AIContextEntry unless context
    context.guards.reject { |g| NON_AUTH_GUARD_KINDS.includes?(g.kind) }
  end

  # Signals worth filtering on: the route/detector/method ones restate
  # method, url and tech, and would make `--signal any` match everything.
  def self.derived_signals(context : AIContext?) : Array(AIContextEntry)
    return [] of AIContextEntry unless context
    context.signals.reject { |s| RESTATING_SIGNAL_SOURCES.includes?(s.source) }
  end

  RESTATING_SIGNAL_SOURCES = {"route", "detector", "http_method"}

  # Whether `query --method` lists a route declared for `declared`. An
  # `ANY` row (nginx, Apache, `router.all`) serves every HTTP verb, so
  # `--method POST` lists it, as `trace` does; `--method ANY` lists only
  # the `ANY` rows.
  def self.method_listed?(methods : Array(String), declared : String) : Bool
    declared = declared.upcase
    methods.includes?(declared) || (::synthetic_any_method?(declared) && methods.any? { |m| ::ALLOWED_HTTP_METHODS.includes?(m) })
  end

  # ---- query filters: AND-ed, comma lists OR -------------------------------

  record Filters,
    methods : Array(String) = [] of String,
    url : String? = nil,
    path : String? = nil,
    projects : Array(String) = [] of String,
    handler : String? = nil,
    techs : Array(String) = [] of String,
    tags : Array(String) = [] of String,
    params : Array(String) = [] of String,
    param_types : Array(String) = [] of String,
    protocols : Array(String) = [] of String,
    guard : Bool? = nil,
    sinks : Array(String) = [] of String,
    sources : Array(String) = [] of String,
    signals : Array(String) = [] of String,
    validators : Array(String) = [] of String,
    # `--exclude-endpoints method:GET` drops GET rows, not the `ANY`
    # catch-alls that `--method GET` lists because they also serve GET.
    methods_exact : Bool = false do
    def matches?(endpoint : Endpoint) : Bool
      unless methods.empty?
        listed = methods_exact ? methods.includes?(endpoint.method.upcase) : EndpointFilter.method_listed?(methods, endpoint.method)
        return false unless listed
      end
      return false unless (u = url).nil? || EndpointFilter.url_matches?(u, endpoint.url)
      return false unless (p = path).nil? || endpoint.details.code_paths.any? { |cp| EndpointFilter.path_glob?(p, cp.path) }
      return false unless projects.empty? || projects.any? { |wanted| EndpointFilter.project_matches?(wanted, endpoint.details.project) }
      return false unless (h = handler).nil? || endpoint.handler.try { |eh| EndpointFilter.glob_or_substring?(h, eh.name) || EndpointFilter.path_glob?(h, eh.path || "") }
      unless techs.empty?
        have = endpoint.details.technologies.empty? ? [endpoint.details.technology].compact : endpoint.details.technologies
        return false unless (have & techs).present?
      end
      return false unless tags.empty? || endpoint.tags.any? { |t| tags.includes?(t.name) }
      # One parameter has to satisfy both `--param` and `--param-type`.
      unless params.empty? && param_types.empty?
        return false unless endpoint.params.any? { |p| param_matches?(p) }
      end
      return false unless protocols.empty? || protocols.includes?(endpoint.protocol)
      context = endpoint.ai_context
      unless (g = guard).nil?
        # An outbound client declaration (Feign, `@HttpExchange`) is not served
        # here, so it is neither guarded nor open.
        return false if endpoint.internal
        return false unless g == !EndpointFilter.auth_guards(context).empty?
      end
      return false unless EndpointFilter.bucket_matches?(sinks, context.try(&.sinks))
      return false unless EndpointFilter.bucket_matches?(sources, context.try(&.sources))
      return false unless EndpointFilter.bucket_matches?(signals, EndpointFilter.derived_signals(context))
      return false unless EndpointFilter.bucket_matches?(validators, context.try(&.validators))
      true
    end

    private def param_matches?(param : Param) : Bool
      return false unless params.empty? || params.any? do |name|
                            param.param_type == "header" ? name.compare(param.name, case_insensitive: true) == 0 : name == param.name
                          end
      param_types.empty? || param_types.includes?(param.param_type) || param_types.includes?(param.request_type)
    end
  end

  # `any` (or an empty bucket filter) is satisfied by a non-empty bucket.
  def self.bucket_matches?(wanted : Array(String), entries : Array(AIContextEntry)?) : Bool
    return true if wanted.empty?
    return false if entries.nil? || entries.empty?
    wanted.includes?("any") || entries.any? { |e| wanted.includes?(e.kind) }
  end

  # A glob when it looks like one, a substring otherwise. The glob is the
  # agent's, not the shell's: `*` and `**` match anything including `/`
  # (every Django URL ends in `/`, `*users*` has to find it), `?` one
  # character, `[...]` a class, and `{`, `}` are literal so a route with
  # `{id}` in it can be matched as written.
  GLOB_CHARS = /[*?\[]/

  def self.glob_or_substring?(pattern : String, value : String) : Bool
    return value.includes?(pattern) unless pattern.matches?(GLOB_CHARS)
    glob_regex(pattern).matches?(value)
  end

  # A pattern rooted at `/` also matches the path of an absolute HTTP URL,
  # so `/admin*` finds `/admin` whether or not `-u` put a host in front of
  # it, in a scan, a live query and a report read with `--from` alike.
  ABSOLUTE_HTTP_URL = /\A(?:https?|wss?):\/\/[^\/?#]*/i

  def self.url_matches?(pattern : String, url : String) : Bool
    return true if glob_or_substring?(pattern, url)
    return false unless pattern.starts_with?('/') && (host = ABSOLUTE_HTTP_URL.match(url))
    path = url[host[0].size..]
    glob_or_substring?(pattern, path.empty? ? "/" : path)
  end

  # Reported paths carry the scan root (`corpus/app/routes/x.ts`), so a glob
  # written from inside the app (`routes/*`) also matches from any `/`.
  def self.path_glob?(pattern : String, value : String) : Bool
    return value.includes?(pattern) unless pattern.matches?(GLOB_CHARS)
    return glob_regex(pattern).matches?(value) if pattern.starts_with?('/') || pattern.starts_with?('*')
    glob_regex(pattern, anchored: false).matches?(value)
  end

  # A project is named by its directory under the scan base, so `services/orders`
  # is that project and not `services/orders-v2`. A glob (same rules as above)
  # matches the whole name. An endpoint with no project matches nothing.
  def self.project_matches?(wanted : String, project : String) : Bool
    return false if project.empty?
    return glob_regex(wanted).matches?(project) if wanted.matches?(GLOB_CHARS)
    wanted.chomp('/') == project
  end

  @@glob_regexes = Hash(String, Regex).new

  private def self.glob_regex(pattern : String, anchored : Bool = true) : Regex
    @@glob_regexes["#{anchored}:#{pattern}"] ||= begin
      body = String.build do |io|
        pattern.each_char do |c|
          case c
          when '*' then io << ".*"
          when '?' then io << '.'
          when '[' then io << '['
          when ']' then io << ']'
          else          io << Regex.escape(c.to_s)
          end
        end
      end
      Regex.new("#{anchored ? "\\A" : "(?:\\A|/)"}#{body}\\z")
    rescue ArgumentError
      # An unbalanced `[`: it was not a glob after all, so substring.
      Regex.new(Regex.escape(pattern))
    end
  end

  # Filter values that no endpoint can satisfy, so a typo (`--sink file`
  # for `file_io`) or a report scanned without `--ai-context` is said out
  # loud instead of returning an empty answer that looks final.
  def self.filter_warnings(endpoints : Array(Endpoint), filters : Filters) : Array(String)
    warnings = [] of String
    asks_context = !filters.guard.nil? || !(filters.sinks.empty? && filters.sources.empty? && filters.signals.empty? && filters.validators.empty?)
    if asks_context && endpoints.none?(&.ai_context)
      warnings << "no endpoint carries ai_context; scan with --ai-context (or drop --from)"
      return warnings
    end
    contexts = endpoints.compact_map(&.ai_context)
    {
      {"method", filters.methods, endpoints.map(&.method.upcase)},
      {"tech", filters.techs, endpoints.flat_map { |e| e.details.technologies.empty? ? [e.details.technology].compact : e.details.technologies }},
      {"tag", filters.tags, endpoints.flat_map(&.tags.map(&.name))},
      {"param", filters.params, endpoints.flat_map(&.params.map(&.name))},
      {"param type", filters.param_types, endpoints.flat_map { |e| e.params.flat_map { |p| [p.param_type, p.request_type] } }},
      {"project", filters.projects.reject(&.matches?(GLOB_CHARS)).map(&.chomp('/')), endpoints.map(&.details.project).reject(&.empty?)},
      {"protocol", filters.protocols, endpoints.map(&.protocol)},
      {"sink kind", filters.sinks, contexts.flat_map(&.sinks.map(&.kind))},
      {"source kind", filters.sources, contexts.flat_map(&.sources.map(&.kind))},
      {"signal kind", filters.signals, contexts.flat_map { |c| derived_signals(c).map(&.kind) }},
      {"validator kind", filters.validators, contexts.flat_map(&.validators.map(&.kind))},
    }.each do |label, wanted, seen|
      seen = seen.uniq.sort!
      unknown = wanted.reject do |k|
        k == "any" || seen.includes?(k) ||
          (label == "method" && method_listed?([k], "ANY") && seen.any? { |m| ::synthetic_any_method?(m) }) ||
          (label == "param" && endpoints.any? do |e|
            e.params.any? { |p| p.param_type == "header" && p.name.compare(k, case_insensitive: true) == 0 }
          end)
      end
      next if unknown.empty?
      # A signal the compact row hides (it restates method/url/tech) is not
      # "unknown"; say why it does not filter.
      if label == "signal kind"
        restating = contexts.flat_map { |c| c.signals.select { |s| RESTATING_SIGNAL_SOURCES.includes?(s.source) }.map(&.kind) }.uniq!
        hidden, unknown = unknown.partition { |k| restating.includes?(k) }
        warnings << "signal #{hidden.join(", ")} restates the row's method, url or tech and does not filter" unless hidden.empty?
        next if unknown.empty?
      end
      warnings << "no endpoint carries #{label} #{unknown.join(", ")}; in this report: #{seen.empty? ? "(none)" : seen.join(", ")}"
    end
    warnings
  end

  # ---- --only-endpoints / --exclude-endpoints terms ----------------------

  # Keys a term may use: the `noir query` filter names, minus the ones whose
  # data does not exist yet where scan applies the filter (right after the
  # optimizer, before status probing, taggers and the AI-context builder).
  KEYS = %w[url method protocol tech project path handler param param-type]
  # One pattern each, as in query: a URL can hold a comma.
  SINGLE_PATTERN_KEYS = %w[url path handler]
  # Query filters that read tags or ai_context, which scan fills in later.
  LATE_KEYS = %w[tag guard no-guard sink source signal validator]

  class TermError < Exception
  end

  # One `--only-endpoints` / `--exclude-endpoints` value: space-separated
  # `key:value` items that must all hold. A bare value starting with `/` is
  # a `url:` pattern.
  record Term, text : String, filters : Filters

  def self.parse_term(text : String) : Term
    tokens = text.split(/\s+/, remove_empty: true)
    raise TermError.new("the value is empty") if tokens.empty?
    values = Hash(String, Array(String)).new
    tokens.each do |token|
      key, value = if token.starts_with?('/')
                     {"url", token}
                   elsif colon = token.index(':')
                     {token[0...colon], token[(colon + 1)..]}
                   else
                     raise TermError.new("#{token.inspect} is neither key:value nor a /path pattern#{hint_for(token)}")
                   end
      if LATE_KEYS.includes?(key)
        raise TermError.new("#{key}: is only known after tagging and AI context, which run after this filter; use `noir query --#{key}` on the report instead")
      end
      unless KEYS.includes?(key)
        raise TermError.new("unknown key #{key.inspect}#{hint_for(key)} (keys: #{KEYS.join(", ")})")
      end
      raise TermError.new("#{key}: given twice; repeat the flag to match either, or use a comma list") if values.has_key?(key)
      items = SINGLE_PATTERN_KEYS.includes?(key) ? [value] : value.split(',').map(&.strip)
      items.reject!(&.empty?)
      raise TermError.new("#{key}: has no value") if items.empty?
      values[key] = items
    end
    empty = [] of String
    filters = Filters.new(
      methods: (values["method"]? || empty).map(&.upcase),
      url: values["url"]?.try(&.first),
      path: values["path"]?.try(&.first),
      projects: values["project"]? || empty,
      handler: values["handler"]?.try(&.first),
      techs: values["tech"]? || empty,
      params: values["param"]? || empty,
      param_types: values["param-type"]? || empty,
      protocols: values["protocol"]? || empty,
    )
    Term.new(text, filters)
  end

  # `CLI:/*` (the probe-filter `METHOD:url` shape) names a method, not a key.
  private def self.hint_for(token : String) : String
    word = token.split(':', 2).first
    return "" unless ::endpoint_method_token?(word)
    "; did you mean method:#{word.upcase}#{word.upcase == ::CLI_ENDPOINT_METHOD ? " or protocol:cli" : ""}?"
  end

  # A term that matched nothing (almost always a typo, which must not read
  # as "there was nothing to exclude"), or a filter that left nothing.
  # A diff scan prints a warning only when both sides raised it (same
  # `term_key`): a diff that removes every CLI command leaves
  # `protocol:cli` matching only the old side, and that is the point.
  record Warning, message : String, term_key : String

  # Keeps the endpoints matching any `only` term (all of them when there is
  # none), then drops those matching any `exclude` term.
  def self.apply(endpoints : Array(Endpoint), only : Array(Term), exclude : Array(Term)) : {Array(Endpoint), Array(Warning)}
    exclude = exclude.map { |term| term.copy_with(filters: term.filters.copy_with(methods_exact: true)) }
    warnings = [] of Warning
    {"--only-endpoints" => only, "--exclude-endpoints" => exclude}.each do |flag, terms|
      terms.each do |term|
        next if endpoints.any? { |e| term.filters.matches?(e) }
        detail = filter_warnings(endpoints, term.filters)
        warnings << Warning.new("#{flag} #{term.text.inspect} matched no endpoint#{detail.empty? ? "" : " (#{detail.join("; ")})"}", "#{flag} #{term.text}")
      end
    end
    kept = endpoints.select do |e|
      (only.empty? || only.any?(&.filters.matches?(e))) && exclude.none?(&.filters.matches?(e))
    end
    if !endpoints.empty? && kept.empty?
      warnings << Warning.new("--only-endpoints / --exclude-endpoints left none of the #{endpoints.size} endpoints", "left-none")
    end
    {kept, warnings}
  end

  # The warnings to print for a scan and, in diff mode, its other side:
  # only those both sides raised.
  def self.merged_warnings(base : Array(Warning), other : Array(Warning)?) : Array(String)
    return base.map(&.message) unless other
    other_keys = other.map(&.term_key).to_set
    base.select { |warning| other_keys.includes?(warning.term_key) }.map(&.message)
  end

  # The terms an options hash carries under `key` (a YAML list, or a single
  # string from a hand-written config file).
  def self.terms(value : YAML::Any?) : Array(Term)
    raw = case v = value.try(&.raw)
          when Array  then v.map(&.to_s)
          when String then v.blank? ? [] of String : [v]
          else             [] of String
          end
    raw.map { |text| parse_term(text) }
  end
end
