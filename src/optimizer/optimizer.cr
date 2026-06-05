require "../models/endpoint"
require "../models/logger"
require "../utils/*"

# Endpoint optimization module that handles endpoint deduplication,
# URL combination, and path parameter extraction
class EndpointOptimizer
  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  @pvalue_rules : Hash(String, Array(PValueRule))

  private struct PValueRule
    property key : String?
    property value : String

    def initialize(@key : String?, @value : String)
    end
  end

  # A URL that already carries its own scheme + authority
  # (e.g. `https://host/path`). The HAR / OAS detectors emit these, so
  # the optimizer must not prepend a target, collapse the `//` after the
  # scheme, or treat the leading segment as a path.
  ABSOLUTE_URL_RE = /\A[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//

  def initialize(@logger : NoirLogger, @options : Hash(String, YAML::Any))
    @pvalue_rules = initialize_pvalue_rules
  end

  # Main optimization workflow - calls all optimization steps
  def optimize(endpoints : Array(Endpoint)) : Array(Endpoint)
    optimized = optimize_endpoints(endpoints)
    optimized = combine_url_and_endpoints(optimized)
    optimized = normalize_url_shapes(optimized)
    optimized = add_path_parameters(optimized)
    optimized
  end

  # Normalize cross-framework URL shapes the analyzers can't always
  # resolve without language context. Rewrites a small set of well-
  # known leaky forms into the canonical `{name}` placeholder so the
  # downstream `add_path_parameters` pass picks them up as path
  # params instead of literal noise.
  #
  # Covered shapes:
  #   - `(?P<name>pattern)` — Python `re_path`-style named groups.
  #     Bleeds through Django's `re_path` route table; rewrite to
  #     `{name}` and drop the regex body.
  #   - `${name}` / `${obj.field}` — JS/TS template literals that
  #     analyzers can't statically resolve (handler files reference
  #     captured variables, not literal paths). Rewrite to `{name}`
  #     (or `{field}` for `${obj.field}`) so the AI/output payload
  #     surfaces it as a path placeholder rather than as a literal
  #     `${...}` segment.
  #   - Python regex anchors `^` (leading) and `$`/`\Z` (trailing) —
  #     `re_path` patterns commonly include these.
  #   - Python regex backslash-escaped dots `\.` — rewrite to plain
  #     `.` for the visible URL.
  #   - Spring `{name:regex}` — strip the inline regex constraint so
  #     the placeholder is `{name}` regardless of framework dialect.
  def normalize_url_shapes(endpoints : Array(Endpoint)) : Array(Endpoint)
    # `Endpoint` is a value-type struct in Crystal, so mutating
    # through the block-local binding only edits a copy. Rewrite
    # via array index so the in-place change actually persists.
    endpoints.each_with_index do |endpoint, idx|
      url = endpoint.url
      next if url.empty?

      # Skip URLs that look like a verbatim regex literal — Express
      # accepts `app.get(/^\/api\/(\d+)$/, handler)` and the route
      # extractor preserves the literal as the URL. The unique
      # signal is escaped slashes (`\/`); plain `\d`/`\w` classes
      # are also legal inside Django/Pyramid `re_path` named
      # groups (`(?P<id>\d+)`), so checking those alone would
      # over-shoot and leave Django patterns un-normalized.
      next if url.includes?("\\/")

      # Python `re_path` named groups: `(?P<name>...)` → `{name}`.
      # Use a hand-walked replacement so the inner regex body (which
      # can contain its own balanced parens / brackets) is consumed
      # correctly without writing a recursive regex.
      url = strip_python_named_groups(url)

      # Spring `{name:regex}` path variables — strip the inline regex
      # constraint so downstream consumers see the canonical `{name}`
      # placeholder. Spring accepts `{id:[0-9]+}`, `{path:.*}`, etc.;
      # the regex body matters to the framework but is noise in the
      # endpoint surface.
      url = url.gsub(/\{([A-Za-z_][A-Za-z0-9_]*):[^{}]+\}/) do |_match|
        "{#{$1}}"
      end

      # JS/TS template-literal interpolations the parser couldn't
      # resolve. Pick the rightmost identifier token in the
      # expression — it's almost always the value-carrying name:
      #   `${id}`                 → `{id}`
      #   `${obj.field}`          → `{field}`
      #   `${get(id)}`            → `{id}`
      #   `${getThing().id}`      → `{id}`
      #   `${utils.fmt(value)}`   → `{value}`
      # Falls back to `{var}` when the expression has no extractable
      # identifier (e.g., `${1+2}` or `${"raw"}`).
      url = url.gsub(/\$\{([^{}]+)\}/) do |_match|
        expr = $1.to_s
        tokens = expr.split(/[^A-Za-z0-9_]/).reject(&.empty?)
        name = tokens.last? || ""
        name.empty? ? "{var}" : "{#{name}}"
      end

      # Strip Python regex anchors at the path boundary.
      url = url.sub(/^\/\^/, "/")
      url = url.sub(/\$$/, "")
      url = url.sub(/\\Z$/, "")
      url = url.sub(/\/\$$/, "/")

      # Backslash-escaped dots (re_path `r"\.json"`) → literal dot.
      url = url.gsub("\\.", ".")

      # Final path double-slash collapse in case the rewrites left an
      # adjacent pair (e.g., trimming a leading `^` after `/`). Skip
      # absolute URLs entirely — the HAR / OAS detectors emit them and
      # the `//` after the scheme is structural, not a path separator.
      url = collapse_path_slashes(url) unless url.matches?(ABSOLUTE_URL_RE)

      endpoint.url = url
      endpoints[idx] = endpoint
    end

    endpoints
  end

  # Rewrites every `(?P<name>...)` occurrence in `url` to `{name}`,
  # consuming the matching `)` even when the inner pattern contains
  # nested parens. Returns `url` unchanged when no named group is
  # present.
  private def strip_python_named_groups(url : String) : String
    return url unless url.includes?("(?P<")

    result = String::Builder.new
    i = 0
    size = url.size
    while i < size
      if i + 3 < size && url[i] == '(' && url[i + 1] == '?' && url[i + 2] == 'P' && url[i + 3] == '<'
        close_name = url.index('>', i + 4)
        unless close_name
          result << url[i..]
          break
        end
        name = url[(i + 4)...close_name]

        # Walk to the matching `)` from after the name's `>`.
        depth = 1
        j = close_name + 1
        while j < size && depth > 0
          ch = url[j]
          case ch
          when '\\'
            j += 2
            next
          when '['
            close_bracket = url.index(']', j + 1) || size
            j = close_bracket + 1
            next
          when '('
            depth += 1
          when ')'
            depth -= 1
          end
          j += 1
        end

        result << "{#{name}}"
        i = j
      else
        result << url[i]
        i += 1
      end
    end

    result.to_s
  end

  # Remove duplicated endpoints and parameters, validate HTTP methods, clean URLs
  def optimize_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
    @logger.info "Optimizing endpoints."
    @logger.sub "➔ Removing duplicated endpoints and params."
    final_map = {} of Tuple(String, String) => Endpoint
    duplicate_count = 0
    allowed_methods = get_allowed_methods

    endpoints.each do |endpoint|
      tiny_tmp = endpoint

      # Normalize the HTTP method to upper case. This makes the dedup
      # key case-insensitive (`get` and `GET` for the same URL are one
      # endpoint, not two) and keeps the emitted method canonical.
      # Unknown verbs fall back to GET.
      upcased_method = tiny_tmp.method.upcase
      if allowed_methods.includes?(upcased_method)
        tiny_tmp.method = upcased_method
      else
        @logger.debug_sub "  - Invalid HTTP method: '#{tiny_tmp.method}' for '#{tiny_tmp.url}', defaulting to GET"
        tiny_tmp.method = "GET"
      end

      # Remove space in param name
      if endpoint.params.present?
        tiny_tmp.params = [] of Param
        endpoint.params.each do |param|
          if !param.name.includes? " "
            param.value = apply_pvalue(param.param_type, param.name, param.value).to_s
            tiny_tmp.params << param
          end
        end
      end

      # Duplicate check
      unless tiny_tmp.url.empty?
        absolute_url = tiny_tmp.url.matches?(ABSOLUTE_URL_RE)

        # Ensure a leading slash for relative URLs. Compare against the
        # `'/'` char literal — comparing the `Char` returned by `[]` to
        # the `"/"` string is always true, which would prepend a slash
        # even to already-rooted URLs (the double-slash collapse below
        # papered over it).
        if !absolute_url && tiny_tmp.url[0] != '/'
          tiny_tmp.url = "/#{tiny_tmp.url}"
        end

        # Collapse accidental double slashes in the path.
        tiny_tmp.url = collapse_path_slashes(tiny_tmp.url) unless absolute_url

        key = {tiny_tmp.method, tiny_tmp.url}

        if final_map.has_key?(key)
          dup = final_map[key]
          @logger.debug_sub "  - Found duplicated endpoint: #{tiny_tmp.method} #{tiny_tmp.url}"
          duplicate_count += 1
          tiny_tmp.params.each do |param|
            existing_param = dup.params.find { |dup_param| dup_param.name == param.name }
            unless existing_param
              dup.params << param
            end
          end
        else
          final_map[key] = tiny_tmp
        end
      end
    end

    @logger.verbose_sub "➔ Total duplicated endpoints: #{duplicate_count}"
    final_map.values
  end

  # Combine target URL with endpoints
  def combine_url_and_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
    tmp = [] of Endpoint
    target_url = @options["url"].to_s

    if target_url.empty?
      endpoints
    else
      @logger.sub "➔ Combining url and endpoints."
      @logger.debug_sub " + Before size: #{endpoints.size}"

      endpoints.each do |endpoint|
        tmp_endpoint = endpoint

        # An endpoint that already carries its own scheme + host (HAR /
        # OAS absolute URLs) is self-contained. Prefixing the target or
        # collapsing its scheme `//` would corrupt it, so pass it
        # through untouched.
        if tmp_endpoint.url.matches?(ABSOLUTE_URL_RE)
          tmp << tmp_endpoint
          next
        end

        # Strip the target only when it is an actual leading prefix.
        # `gsub` here would also rewrite a target host that merely
        # appears inside a query value (e.g.
        # `/proxy?next=https://host/x`), dropping it from the path.
        if tmp_endpoint.url.starts_with?(target_url)
          tmp_endpoint.url = tmp_endpoint.url[target_url.size..]
        end

        tmp_endpoint.url = collapse_path_slashes(tmp_endpoint.url)
        unless tmp_endpoint.url.empty?
          if target_url[-1] == '/' && tmp_endpoint.url[0] == '/'
            tmp_endpoint.url = tmp_endpoint.url[1..]
          elsif target_url[-1] != '/' && tmp_endpoint.url[0] != '/'
            tmp_endpoint.url = "/#{tmp_endpoint.url}"
          end
        end

        tmp_endpoint.url = target_url + tmp_endpoint.url
        tmp << tmp_endpoint
      end

      @logger.debug_sub " + After size: #{tmp.size}"
      tmp
    end
  end

  # Add path parameters by parsing URL patterns
  def add_path_parameters(endpoints : Array(Endpoint)) : Array(Endpoint)
    @logger.sub "➔ Adding path parameters by URL."
    final = [] of Endpoint

    endpoints.each do |endpoint|
      new_endpoint = endpoint

      # `{param}` patterns. The placeholder may sit at a segment
      # boundary (`/{id}`) or share a segment with sibling variables
      # separated by a comma — Spring's matrix-style `@GetMapping(
      # "/bbox/{xMin},{yMin},{xMax},{yMax}")` packs four into one
      # segment, so allow a leading `,` as well as `/` (otherwise only
      # the first variable in the segment is captured).
      endpoint.url.scan(/[\/,]\{([^}]+)\}/).each do |match|
        raw = match[1]
        # Strip a leading `*` from catch-all path variables (Spring,
        # Armeria and ASP.NET all spell the rest-of-path capture as
        # `{*name}`, e.g. `/files/{*path}`) and any inline regex/type
        # constraint after `:`. The parameter is named `name`, not
        # `*name` or `name:regex`.
        param = raw.split(":")[0].lstrip('*')
        next if param.empty?
        new_endpoint.url = register_path_param(new_endpoint.url, new_endpoint.params, "{#{raw}}", param)
      end

      # `/:param` patterns.
      endpoint.url.scan(/\/:([^\/{}]+)/).each do |match|
        raw = match[1]
        # The capture greedily includes any literal suffix that follows
        # the param within the same segment (e.g. Play's `/:lang.json`
        # or `/:id.gif`). Path param names are identifiers, so keep only
        # the leading identifier and drop the extension/format suffix.
        param = leading_path_param(raw)
        next unless param
        new_endpoint.url = register_path_param(new_endpoint.url, new_endpoint.params, ":#{raw}", param)
      end

      # `<param>` patterns (Django / Marten style).
      endpoint.url.scan(/<([^>]+)>/).each do |match|
        raw = match[1]
        param = angle_bracket_param(raw)
        # Skip regex fragments. Play declares constrained path params as
        # `$name<regex>`, so the framework analyzer already recorded
        # `name`; the `<regex>` body (e.g. `\w{8}`, `[\w-]{2,6}`) is not
        # a param name.
        next unless valid_path_param_name?(param)
        new_endpoint.url = register_path_param(new_endpoint.url, new_endpoint.params, "<#{raw}>", param)
      end

      # `/*param` patterns (wildcard / glob).
      endpoint.url.scan(/\/\*([^\/]+)/).each do |match|
        raw = match[1]
        # Only named splats are parameters (`/files/*path` -> `path`).
        # A bare glob like Armeria's `glob:/glob/**` captures `*`, and
        # a gRPC resource template leaves a trailing `}` — neither is a
        # real parameter name.
        next unless valid_path_param_name?(raw)
        new_endpoint.url = register_path_param(new_endpoint.url, new_endpoint.params, "*#{raw}", raw)
      end

      reconcile_ruby_path_params(new_endpoint)

      final << new_endpoint
    end

    final
  end

  # Substitute a configured path-param value into the URL when one is
  # set, then record the param (deduped by name). Returns the updated
  # URL; `params` is mutated in place — it is the endpoint's own array
  # reference, so the push persists on the caller's struct.
  private def register_path_param(url : String, params : Array(Param), placeholder : String, name : String) : String
    value = apply_pvalue("path", name, "")
    url = url.gsub(placeholder, value) unless value.empty?
    params << Param.new(name, "", "path") unless path_param_present?(params, name)
    url
  end

  # Resolve the param name from a `<...>` capture, handling both Django
  # `<type:name>` and Marten `<name:type>` ordering. When the first
  # `:`-segment is a known converter type it's Django ordering; otherwise
  # the name comes first.
  private def angle_bracket_param(raw : String) : String
    parts = raw.split(":")
    return parts[0] if parts.size <= 1
    parts[0] =~ /^(int|str|string|slug|uuid|float|bool|path)$/ ? parts[1] : parts[0]
  end

  # Reconcile path params against same-named query/body params for Ruby
  # frameworks. Rack/Rails frameworks (Rails, Sinatra, Hanami, Roda,
  # Grape) merge captured path segments into a single `params` hash, so a
  # handler that reads `params[:id]` for a `/users/:id` route is reading
  # the path value — not a separate query/body field. Once the path type
  # is known, the duplicate non-path entry is redundant. This is NOT done
  # globally: frameworks with separate path/query/body buckets (Lucky's
  # typed params, Express `req.params` vs `req.query`) carry both.
  private def reconcile_ruby_path_params(endpoint : Endpoint) : Nil
    tech = endpoint.details.technology
    return unless tech && tech.starts_with?("ruby_")

    path_names = endpoint.params.compact_map { |p| p.param_type == "path" ? p.name : nil }
    return if path_names.empty?

    path_name_set = path_names.to_set
    endpoint.params.reject! { |p| p.param_type != "path" && path_name_set.includes?(p.name) }
  end

  # Collapse accidental duplicate slashes in the *path* only. A query or
  # fragment may legitimately embed an absolute URL — e.g. an OAuth
  # callback `/cb?redirect_uri=https://app/x` — whose `//` must survive.
  # Callers gate this on the URL being relative, so the leading
  # `scheme://` is never in play here.
  private def collapse_path_slashes(url : String) : String
    return url unless url.includes?("//")

    query = url.index('?')
    fragment = url.index('#')
    cut = if query && fragment
            Math.min(query, fragment)
          else
            query || fragment
          end

    return url.gsub_repeatedly("//", "/") unless cut
    url[0...cut].gsub_repeatedly("//", "/") + url[cut..]
  end

  # A path param name is a plain identifier; anything else (a regex fragment,
  # a glob, a type expression) is not a real parameter name.
  private def valid_path_param_name?(name : String) : Bool
    !name.empty? && !!name.match(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
  end

  # A URL cannot carry two path params with the same name, so dedup by name
  # alone. An exact-struct check is too strict: analyzers that record a type
  # in the param `value` (e.g. Haskell's Servant/Yesod store `Capture "id" Int`
  # as `Param("id", "Int", "path")`) would otherwise not match the empty-value
  # param this pass derives from the URL, producing a duplicate.
  private def path_param_present?(params : Array(Param), name : String) : Bool
    params.any? { |param| param.param_type == "path" && param.name == name }
  end

  # Drop a literal format/extension suffix that shares the segment with the
  # param (e.g. Play's `/:lang.json` -> `lang`, `/:id.gif` -> `id`). The split
  # is intentionally limited to the `.` boundary so optional markers and other
  # framework suffixes (e.g. Express's `/:id?`) are preserved verbatim.
  private def leading_path_param(raw : String) : String?
    name = raw.split('.', 2).first
    name.empty? ? nil : name
  end

  # Apply parameter values based on configuration
  def apply_pvalue(param_type, param_name, param_value) : String
    if rules = @pvalue_rules[param_type]?
      rules.each do |rule|
        if rule.key.nil? || rule.key == param_name
          return rule.value
        end
      end
    end

    param_value.to_s
  end

  private def initialize_pvalue_rules : Hash(String, Array(PValueRule))
    rules = Hash(String, Array(PValueRule)).new
    param_types = ["query", "json", "form", "header", "cookie", "path"]
    global_pvalue = @options["set_pvalue"].as_a

    param_types.each do |type|
      pvalue_target = case type
                      when "query"  then @options["set_pvalue_query"]
                      when "json"   then @options["set_pvalue_json"]
                      when "form"   then @options["set_pvalue_form"]
                      when "header" then @options["set_pvalue_header"]
                      when "cookie" then @options["set_pvalue_cookie"]
                      when "path"   then @options["set_pvalue_path"]
                      else               YAML::Any.new([] of YAML::Any)
                      end

      merged_pvalue_target = [] of YAML::Any
      merged_pvalue_target.concat(pvalue_target.as_a)
      merged_pvalue_target.concat(global_pvalue)

      rules[type] = parse_rules(merged_pvalue_target)
    end

    rules
  end

  private def parse_rules(yaml_rules : Array(YAML::Any)) : Array(PValueRule)
    parsed_rules = [] of PValueRule
    yaml_rules.each do |pvalue|
      pvalue_str = pvalue.to_s
      key = nil
      value = pvalue_str

      if pvalue_str.includes?("=") || pvalue_str.includes?(":")
        first_equal = pvalue_str.index("=")
        first_colon = pvalue_str.index(":")

        if first_equal && (!first_colon || first_equal < first_colon)
          split = pvalue_str.split("=", 2)
          key = split[0]
          value = split[1]
        elsif first_colon
          split = pvalue_str.split(":", 2)
          key = split[0]
          value = split[1]
        end
      end

      if key == "*"
        key = nil
      end

      parsed_rules << PValueRule.new(key, value)
    end
    parsed_rules
  end

  # Get allowed HTTP methods. AsyncAPI verbs (`PUBLISH`, `SUBSCRIBE`,
  # `SEND`, `RECEIVE`) ride along so the optimizer leaves event-driven
  # endpoints alone — DAST consumers route on these, and downgrading
  # them to `GET` would collapse publish + subscribe into one row.
  private def get_allowed_methods : Array(String)
    ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE", "CONNECT", "QUERY", "ANY",
     "PUBLISH", "SUBSCRIBE", "SEND", "RECEIVE"]
  end
end
