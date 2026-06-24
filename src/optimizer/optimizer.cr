require "../models/endpoint"
require "../models/logger"
require "../utils/*"

# Endpoint optimization module that handles endpoint deduplication,
# URL combination, and path parameter extraction
class EndpointOptimizer
  # Generic request headers a browser/HTTP client always sends; they carry no
  # endpoint-specific signal, so collection imports that surface them as params
  # are treated as noise during dedup.
  COLLECTION_NOISE_HEADERS = Set{"user-agent", "accept", "content-type", "host", "origin", "referer", "x-requested-with"}

  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  @pvalue_rules : Hash(String, Array(PValueRule))
  @source_scope_cache : Hash(String, String)

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
  ABSOLUTE_URL_RE        = /\A[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//
  PROJECT_MANIFEST_FILES = {
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "settings.gradle.kts",
    "shard.yml",
    "package.json",
    "go.mod",
    "Cargo.toml",
    "pyproject.toml",
    "mix.exs",
  }

  def initialize(@logger : NoirLogger, @options : Hash(String, YAML::Any))
    @pvalue_rules = initialize_pvalue_rules
    @source_scope_cache = Hash(String, String).new
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
  #   - Postman / Express-style `:name` path segments — rewrite to
  #     `{name}` so collections merge with framework analyzers that
  #     already emit the canonical placeholder shape.
  def normalize_url_shapes(endpoints : Array(Endpoint)) : Array(Endpoint)
    # `Endpoint` is a value-type struct in Crystal, so mutating
    # through the block-local binding only edits a copy. Rewrite
    # via array index so the in-place change actually persists.
    endpoints.each_with_index do |endpoint, idx|
      # Mobile deep-link URLs are not HTTP route templates: a `${...}`
      # there is an unresolved gradle manifest placeholder (kept verbatim
      # and tagged by the Android analyzer), not a JS template literal.
      next if endpoint.non_http?
      endpoint.url = normalize_url_shape(endpoint.url)
      endpoints[idx] = endpoint
    end

    endpoints
  end

  private def normalize_url_shape(url : String, normalize_colon_segments : Bool = false) : String
    return url if url.empty?

    # Skip URLs that look like a verbatim regex literal — Express
    # accepts `app.get(/^\/api\/(\d+)$/, handler)` and the route
    # extractor preserves the literal as the URL. The unique signal is
    # escaped slashes (`\/`).
    return url if url.includes?("\\/")

    normalized = url

    # Python `re_path` named groups: `(?P<name>...)` → `{name}`.
    normalized = strip_python_named_groups(normalized)

    # Spring `{name:regex}` path variables — strip the inline regex
    # constraint so downstream consumers see the canonical placeholder.
    normalized = normalized.gsub(/\{([A-Za-z_][A-Za-z0-9_]*):[^{}]+\}/) do |_match|
      "{#{$1}}"
    end

    # Postman-style full path segments: `/:id` → `/{id}`.
    # Keep embedded placeholders such as `/profiles/celeb_:USERNAME`
    # untouched because those are concrete-example strings, not a
    # segment-level route template.
    if normalize_colon_segments
      normalized = normalized.gsub(/(^|\/):([A-Za-z_][A-Za-z0-9_]*)/) do |_match|
        "#{$1}{#{$2}}"
      end
    end

    # JS/TS template-literal interpolations the parser couldn't resolve.
    normalized = normalized.gsub(/\$\{([^{}]+)\}/) do |_match|
      expr = $1.to_s
      tokens = expr.split(/[^A-Za-z0-9_]/).reject(&.empty?)
      name = tokens.last? || ""
      name.empty? ? "{var}" : "{#{name}}"
    end

    # Strip Python regex anchors at the path boundary.
    normalized = normalized.sub(/^\/\^/, "/")
    normalized = normalized.sub(/\$$/, "")
    normalized = normalized.sub(/\\Z$/, "")
    normalized = normalized.sub(/\/\$$/, "/")

    # Backslash-escaped dots (re_path `r"\.json"`) → literal dot.
    normalized = normalized.gsub("\\.", ".")

    # Final path double-slash collapse in case the rewrites left an
    # adjacent pair. Skip absolute URLs entirely; the `//` after the
    # scheme is structural, not a path separator.
    normalized = collapse_path_slashes(normalized) unless normalized.matches?(ABSOLUTE_URL_RE)

    normalized
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
    final_map = {} of Tuple(String, String, String) => Endpoint
    duplicate_count = 0
    allowed_methods = get_allowed_methods
    cross_tech_keys = cross_technology_duplicate_keys(endpoints, allowed_methods)

    endpoints.each do |endpoint|
      tiny_tmp = endpoint

      # Normalize the HTTP method to upper case. This makes the dedup
      # key case-insensitive (`get` and `GET` for the same URL are one
      # endpoint, not two) and keeps the emitted method canonical.
      # Unknown verbs fall back to GET.
      upcased_method = tiny_tmp.method.upcase
      if tiny_tmp.cli?
        # CLI endpoints carry the synthetic "CLI" verb, not an HTTP method;
        # keep it intact instead of coercing the "unknown verb" to GET.
        tiny_tmp.method = upcased_method
      elsif allowed_methods.includes?(upcased_method)
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
        # papered over it). Mobile deep links are exempt: an unresolved
        # `@string/...://` or `${...}://` scheme isn't a relative path, so
        # rooting it (`/@string/...`) would corrupt the URL.
        if !absolute_url && tiny_tmp.url[0] != '/' && !tiny_tmp.non_http?
          tiny_tmp.url = "/#{tiny_tmp.url}"
        end

        # Mobile deep-link URLs are kept verbatim: a `${...}` there is an
        # unresolved gradle manifest placeholder, not a JS template literal
        # for the shape-normalizer to rewrite.
        tiny_tmp.url = normalize_url_shape(tiny_tmp.url) unless tiny_tmp.non_http?
        dedup_url = tiny_tmp.non_http? ? tiny_tmp.url : normalize_url_shape(tiny_tmp.url, collection_endpoint?(tiny_tmp))

        key = {tiny_tmp.method, dedup_url, endpoint_source_scope(tiny_tmp, cross_tech_keys)}

        if final_map.has_key?(key)
          dup = final_map[key]
          @logger.debug_sub "  - Found duplicated endpoint: #{tiny_tmp.method} #{tiny_tmp.url}"
          duplicate_count += 1
          if graphql_endpoint?(dup) || graphql_endpoint?(tiny_tmp)
            merge_graphql_params(dup, tiny_tmp)
          else
            merge_params(dup, tiny_tmp, source_collection_pair?(dup, tiny_tmp))
          end
          tiny_tmp.tags.each { |tag| merge_tag(dup, tag) }
          tiny_tmp.callees.each do |callee|
            dup.push_callee(callee)
          end
          tiny_tmp.details.code_paths.each do |path_info|
            dup.details.add_path(path_info) unless dup.details.code_paths.any? { |existing| existing == path_info }
          end
          dup = promote_source_context(dup, tiny_tmp)
          final_map[key] = dup
        else
          final_map[key] = tiny_tmp
        end
      end
    end

    @logger.verbose_sub "➔ Total duplicated endpoints: #{duplicate_count}"
    merged = merge_concrete_example_endpoints(final_map.values)
    prune_collection_graphql_transport_endpoints(merged)
  end

  private def merge_params(target : Endpoint, source : Endpoint, drop_collection_noise : Bool = false) : Nil
    source.params.each do |param|
      next if drop_collection_noise && collection_noise_param?(source, param)

      existing_param = target.params.find { |target_param| target_param.name == param.name && target_param.param_type == param.param_type }
      target.params << param unless existing_param
    end
  end

  private def merge_concrete_example_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
    removed = Set(Int32).new

    endpoints.each_with_index do |source, source_idx|
      next if removed.includes?(source_idx)
      next unless concrete_example_source?(source)

      endpoints.each_with_index do |target, target_idx|
        next if source_idx == target_idx || removed.includes?(target_idx)
        next unless source.method == target.method
        next unless templated_endpoint?(target)
        next unless template_matches_concrete_example?(target.url, source.url)

        target = merge_endpoint_context(target, source)
        endpoints[target_idx] = target
        removed << source_idx
        break
      end
    end

    merged = [] of Endpoint
    endpoints.each_with_index do |endpoint, idx|
      merged << endpoint unless removed.includes?(idx)
    end
    merged
  end

  private def concrete_example_source?(endpoint : Endpoint) : Bool
    return false if endpoint.url.empty?
    return false if endpoint.url.matches?(ABSOLUTE_URL_RE)
    return false if templated_url?(endpoint.url)
    return false if graphql_endpoint?(endpoint)
    collection_endpoint?(endpoint)
  end

  private def templated_endpoint?(endpoint : Endpoint) : Bool
    return false if endpoint.url.empty?
    return false if endpoint.url.matches?(ABSOLUTE_URL_RE)
    return false if graphql_endpoint?(endpoint)
    templated_url?(endpoint.url)
  end

  private def templated_url?(url : String) : Bool
    url.includes?("{") && url.includes?("}")
  end

  private def collection_endpoint?(endpoint : Endpoint) : Bool
    {"insomnia", "postman"}.includes?(endpoint.details.technology || "")
  end

  private def source_collection_pair?(target : Endpoint, source : Endpoint) : Bool
    collection_endpoint?(target) != collection_endpoint?(source)
  end

  private def collection_noise_param?(endpoint : Endpoint, param : Param) : Bool
    return false unless collection_endpoint?(endpoint)

    collection_noise_header_param?(param)
  end

  private def collection_noise_header_param?(param : Param) : Bool
    return false unless param.param_type == "header"

    COLLECTION_NOISE_HEADERS.includes?(param.name.downcase)
  end

  private def template_matches_concrete_example?(template_url : String, concrete_url : String) : Bool
    template_segments = comparable_path_segments(template_url)
    concrete_segments = comparable_path_segments(concrete_url)
    return false unless template_segments.size == concrete_segments.size

    matched_placeholder = false
    template_segments.each_with_index do |template_segment, idx|
      concrete_segment = concrete_segments[idx]
      if placeholder_segment?(template_segment)
        return false unless example_path_value?(concrete_segment)
        matched_placeholder = true
      elsif template_segment != concrete_segment
        return false
      end
    end

    matched_placeholder
  end

  private def comparable_path_segments(url : String) : Array(String)
    path = url.split('?').first.split('#').first
    path.split('/').reject(&.empty?)
  end

  private def placeholder_segment?(segment : String) : Bool
    !!segment.match(/\A\{[A-Za-z_][A-Za-z0-9_]*(?::[^{}]+)?\}\z/)
  end

  private def example_path_value?(segment : String) : Bool
    return true if segment.matches?(/\A\d+\z/)
    return true if segment.matches?(/\A[0-9a-fA-F]{24}\z/)
    return true if segment.matches?(/\A[^\/{}]*:[A-Za-z_][A-Za-z0-9_]*[^\/{}]*\z/)
    segment.matches?(/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/)
  end

  private def merge_endpoint_context(target : Endpoint, source : Endpoint) : Endpoint
    if graphql_endpoint?(target) || graphql_endpoint?(source)
      merge_graphql_params(target, source)
    else
      merge_params(target, source, source_collection_pair?(target, source))
    end

    source.tags.each { |tag| merge_tag(target, tag) }
    source.callees.each do |callee|
      target.push_callee(callee)
    end
    source.details.code_paths.each do |path_info|
      target.details.add_path(path_info) unless target.details.code_paths.any? { |existing| existing == path_info }
    end
    target = promote_source_context(target, source)

    target
  end

  private def merge_tag(target : Endpoint, tag : Tag) : Nil
    return if duplicate_graphql_operation_tag?(target, tag)

    target.add_tag(tag)
  end

  private def duplicate_graphql_operation_tag?(target : Endpoint, tag : Tag) : Bool
    return false unless graphql_operation_tag?(tag)

    if existing_index = target.tags.index do |existing|
         graphql_operation_tag?(existing) &&
         existing.name == tag.name &&
         existing.description == tag.description
       end
      target.tags[existing_index] = tag if tag.tagger == "graphql_sdl_analyzer"
      return true
    end

    false
  end

  private def graphql_operation_tag?(tag : Tag) : Bool
    tag.name == "graphql" &&
      tag.description.matches?(/^(Query|Mutation|Subscription|Schema|Object|Field)\./)
  end

  private def promote_source_context(target : Endpoint, source : Endpoint) : Endpoint
    return target unless collection_endpoint?(target)
    return target if collection_endpoint?(source)

    details = target.details
    details.technology = source.details.technology if source.details.technology
    target.url = source.url

    promoted = [] of PathInfo
    source.details.code_paths.each do |path_info|
      promoted << path_info unless promoted.any? { |existing| existing == path_info }
    end
    target.details.code_paths.each do |path_info|
      promoted << path_info unless promoted.any? { |existing| existing == path_info }
    end
    details.code_paths = promoted
    target.details = details
    target.params.reject! { |param| collection_noise_header_param?(param) }
    target
  end

  private def prune_collection_graphql_transport_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
    operation_paths = Set(String).new
    endpoints.each do |endpoint|
      next unless graphql_operation_endpoint?(endpoint)
      operation_paths << graphql_transport_path(endpoint.url)
    end
    return endpoints if operation_paths.empty?

    endpoints.reject do |endpoint|
      collection_graphql_transport_noise?(endpoint, operation_paths)
    end
  end

  private def collection_graphql_transport_noise?(endpoint : Endpoint, operation_paths : Set(String)) : Bool
    return false unless collection_endpoint?(endpoint)
    return false unless endpoint.method == "POST"
    return false unless operation_paths.includes?(graphql_transport_path(endpoint.url))
    return false if endpoint.url.includes?("#")

    endpoint.params.all? { |param| collection_noise_header_param?(param) }
  end

  private def graphql_operation_endpoint?(endpoint : Endpoint) : Bool
    endpoint.url.matches?(/#[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*/)
  end

  private def graphql_transport_path(url : String) : String
    url.split('#', 2).first
  end

  private def cross_technology_duplicate_keys(endpoints : Array(Endpoint), allowed_methods : Array(String)) : Set(Tuple(String, String))
    technologies_by_key = Hash(Tuple(String, String), Set(String)).new
    framework_scopes_by_key = Hash(Tuple(String, String), Set(String)).new

    endpoints.each do |endpoint|
      url = normalized_dedup_url(endpoint)
      next if url.empty?

      method = normalized_dedup_method(endpoint.method, allowed_methods)
      key = {method, url}
      (technologies_by_key[key] ||= Set(String).new) << (endpoint.details.technology || "")

      scope = framework_source_scope(endpoint)
      (framework_scopes_by_key[key] ||= Set(String).new) << scope unless scope.empty?
    end

    keys = Set(Tuple(String, String)).new
    technologies_by_key.each do |key, technologies|
      next unless technologies.size > 1
      # Neutralizing the scope merges a collection endpoint with the framework
      # one at the same path. But when 2+ distinct build-module scopes share the
      # path, neutralizing would also collapse those distinct multi-module
      # endpoints into one, so keep their scopes intact in that case.
      next if (framework_scopes_by_key[key]?.try(&.size) || 0) > 1
      keys << key
    end
    keys
  end

  private def normalized_dedup_method(method : String, allowed_methods : Array(String)) : String
    upcased_method = method.upcase
    # CLI endpoints use the synthetic "CLI" verb; keep it so their cross-tech
    # dedup key matches the method preserved in the main loop (which exempts
    # cli? from the GET fallback) instead of being coerced to "GET".
    return upcased_method if upcased_method == "CLI"
    allowed_methods.includes?(upcased_method) ? upcased_method : "GET"
  end

  private def normalized_dedup_url(endpoint : Endpoint) : String
    url = endpoint.url
    return "" if url.empty?

    normalized = url
    absolute_url = normalized.matches?(ABSOLUTE_URL_RE)
    normalized = "/#{normalized}" if !absolute_url && normalized[0] != '/' && !endpoint.non_http?
    return normalized if endpoint.non_http?
    normalized = normalize_url_shape(normalized, collection_endpoint?(endpoint))
    normalized
  end

  private def endpoint_source_scope(endpoint : Endpoint, cross_tech_keys : Set(Tuple(String, String))) : String
    return "" if cross_tech_keys.includes?({endpoint.method, endpoint.url})
    framework_source_scope(endpoint)
  end

  # The build-module scope an endpoint carries on its own merits (ignoring any
  # cross-technology neutralization). Only scoped framework endpoints get one;
  # collection / graphql / static endpoints stay unscoped.
  private def framework_source_scope(endpoint : Endpoint) : String
    return "" unless endpoint.details.technology == "kotlin_spring"
    return "" if graphql_endpoint?(endpoint)
    return "" if kotlin_spring_static_asset?(endpoint)

    first_path = endpoint.details.code_paths.first?.try(&.path)
    return "" unless first_path

    source_project_scope(first_path)
  end

  private def kotlin_spring_static_asset?(endpoint : Endpoint) : Bool
    return false unless endpoint.method == "GET"

    first_path = endpoint.details.code_paths.first?.try(&.path)
    return false unless first_path

    normalized = first_path.gsub('\\', '/')
    {
      "/src/main/resources/META-INF/resources/",
      "/src/main/resources/resources/",
      "/src/main/resources/static/",
      "/src/main/resources/public/",
    }.any? { |marker| normalized.includes?(marker) }
  end

  private def source_project_scope(path : String) : String
    return "" if path.empty?
    @source_scope_cache[path] ||= begin
      scope = ""
      dir = File.directory?(path) ? path : File.dirname(path)

      while dir && !dir.empty? && dir != "."
        if PROJECT_MANIFEST_FILES.any? { |manifest| File.exists?(File.join(dir, manifest)) }
          scope = File.expand_path(dir)
          break
        end

        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end

      scope
    end
  end

  private def merge_graphql_params(target : Endpoint, source : Endpoint) : Nil
    target_sdl = graphql_sdl_endpoint?(target)
    source_sdl = graphql_sdl_endpoint?(source)

    source.params.each do |param|
      if graphql_doc_param?(param)
        if existing_index = target.params.index { |target_param| target_param.name == param.name && target_param.param_type == param.param_type }
          target.params[existing_index] = param if source_sdl && !target_sdl
        else
          target.params << param
        end
      else
        existing_param = target.params.find { |target_param| target_param.name == param.name && target_param.param_type == param.param_type }
        target.params << param unless existing_param
      end
    end

    prune_graphql_argument_params(target) if target_sdl || source_sdl

    if source_sdl && !target_sdl
      details = target.details
      details.technology = source.details.technology
      target.details = details
    end
  end

  private def graphql_endpoint?(endpoint : Endpoint) : Bool
    endpoint.url.includes?("#Query.") ||
      endpoint.url.includes?("#Mutation.") ||
      endpoint.url.includes?("#Subscription.")
  end

  private def graphql_sdl_endpoint?(endpoint : Endpoint) : Bool
    tech = endpoint.details.technology
    return true if tech == "graphql_sdl"

    endpoint.tags.any? { |tag| tag.tagger == "graphql_sdl_analyzer" }
  end

  private def graphql_doc_param?(param : Param) : Bool
    param.param_type == "json" &&
      param.name.starts_with?("graphql_") &&
      param.value.matches?(/\A\s*(?:query|mutation|subscription)\b/)
  end

  private def prune_graphql_argument_params(endpoint : Endpoint) : Nil
    return unless endpoint.params.any? { |param| graphql_doc_param?(param) }

    allowed_names = graphql_document_arg_names(endpoint)
    expanded_input_names = graphql_expanded_input_argument_names(endpoint)
    endpoint.params.reject! do |param|
      param.param_type == "json" &&
        !graphql_doc_param?(param) &&
        !graphql_input_field_param?(param) &&
        (!allowed_names.includes?(param.name) || expanded_input_names.includes?(param.name))
    end
  end

  private def graphql_input_field_param?(param : Param) : Bool
    param.tags.any? { |tag| graphql_input_field_tag?(tag) }
  end

  private def graphql_expanded_input_argument_names(endpoint : Endpoint) : Array(String)
    names = [] of String
    endpoint.params.each do |param|
      param.tags.each do |tag|
        next unless graphql_input_field_tag?(tag)
        names << tag.description unless tag.description.empty?
      end
    end
    names.uniq
  end

  private def graphql_input_field_tag?(tag : Tag) : Bool
    tag.name == "graphql-input-field" &&
      {"kotlin_spring_graphql_analyzer", "graphql_sdl_analyzer"}.includes?(tag.tagger)
  end

  private def graphql_document_arg_names(endpoint : Endpoint) : Array(String)
    names = [] of String
    endpoint.params.each do |param|
      next unless graphql_doc_param?(param)
      names.concat(graphql_arg_names_from_document(param.value))
    end
    names.uniq
  end

  private def graphql_arg_names_from_document(document : String) : Array(String)
    match = document.match(/\A\s*(?:query|mutation|subscription)(?:\s+[A-Za-z_][A-Za-z0-9_]*)?\s*\(([^)]*)\)/)
    return [] of String unless match

    names = [] of String
    match[1].scan(/\$([A-Za-z_][A-Za-z0-9_]*)\s*:/) do |arg_match|
      names << arg_match[1]
    end
    names
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
        # through untouched. Mobile deep links (incl. ones with an
        # unresolved `@string/...://` scheme) are app URLs, not paths under
        # the scanned host, so they are never base-joined either.
        if tmp_endpoint.url.matches?(ABSOLUTE_URL_RE) || tmp_endpoint.non_http?
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
      # CLI command URLs are kept verbatim — a `cli://tool/serve` segment is
      # not a path-parameter template. Mobile deep links are NOT skipped here:
      # their `myapp://host/:id` URLs legitimately carry path params that this
      # pass extracts.
      if endpoint.cli?
        final << endpoint
        next
      end

      new_endpoint = endpoint

      # `{param}` patterns. A placeholder may sit at a segment boundary
      # (`/{id}`) or share a segment with literal separators
      # (`/{slug}_{pk}`, `/{name}.json`, `/{x},{y}`). Scan all brace
      # placeholders in the URL instead of assuming the preceding
      # character is `/` or `,`.
      endpoint.url.scan(/\{([^}]+)\}/).each do |match|
        raw = match[1]
        # Strip a leading `*` from catch-all path variables (Spring,
        # Armeria and ASP.NET all spell the rest-of-path capture as
        # `{*name}`, e.g. `/files/{*path}`) and any inline regex/type
        # constraint after `:`. The parameter is named `name`, not
        # `*name` or `name:regex`.
        param = raw.split(":")[0].lstrip('*')
        next unless valid_path_param_name?(param)
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

  # Drop literal suffixes that share the segment with the param (e.g. Play's
  # `/:lang.json` -> `lang`, Fiber/Express optional markers `/:id?` -> `id`,
  # and Express regex constraints `/:id(\\d+)` -> `id`). Path param names are
  # identifiers; anything after the leading identifier describes the segment,
  # not the parameter name.
  #
  # Hyphens are part of the identifier — kebab-case path params are idiomatic
  # in Clojure (`/:artifact-id`, `/:group-id`) and legal in several other
  # route DSLs. Excluding `-` truncated `artifact-id` to `artifact`, adding a
  # phantom param that disagreed with the name the analyzer already recorded.
  private def leading_path_param(raw : String) : String?
    match = raw.match(/\A([A-Za-z_][A-Za-z0-9_-]*)/)
    match ? match[1] : nil
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
