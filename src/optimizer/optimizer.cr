require "../models/endpoint"
require "../models/logger"
require "../utils/*"
require "./optimizer/graphql"
require "./optimizer/path_params"
require "./optimizer/pvalue"
require "./optimizer/url_shapes"

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

  # Stable ordering key: source location first, then technology as a
  # tiebreak for endpoints that carry no code path (static/public-dir
  # serving endpoints, spec-derived ones, etc). `url`/`method` alone
  # cannot break such ties — every endpoint sharing a dedup key already
  # has the same url and method, by definition — so without `technology`
  # here, endpoints with an empty code path (a common shape: multiple
  # frameworks each serving an identically-named asset from their own
  # public/ dir) all collapse to the same `("", -1, url, method)` key.
  # `Array#sort_by` is not a stable sort in Crystal, so those ties would
  # still resolve to "whichever fiber won" — the exact non-determinism
  # this sort exists to remove — making the winning `technology` flip
  # between runs on a single machine, not just across machines.
  private def endpoint_order_key(endpoint : Endpoint) : Tuple(String, Int32, String, String, String)
    code_path = endpoint.details.code_paths.first?
    {
      code_path.try(&.path) || "",
      code_path.try(&.line) || -1,
      endpoint.url,
      endpoint.method,
      endpoint.details.technology || "",
    }
  end

  # Remove duplicated endpoints and parameters, validate HTTP methods, clean URLs
  def optimize_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
    @logger.info "Optimizing endpoints."
    @logger.sub "➔ Removing duplicated endpoints and params."
    final_map = {} of Tuple(String, String, String) => Endpoint
    duplicate_count = 0
    allowed_methods = get_allowed_methods
    cross_tech_keys = cross_technology_duplicate_keys(endpoints, allowed_methods)

    # `parallel_analyze` does not preserve input order: files go to N
    # workers through a bounded channel, so collection order depends on
    # the worker count, which is derived from `System.cpu_count`. The
    # dedup below is first-wins — the first endpoint seen for a key keeps
    # its `details` and later duplicates only merge params/tags into it —
    # so without a stable order the reported file:line for a duplicated
    # route changes with the machine's core count, and JSON/YAML output
    # diffs between machines for no real reason.
    #
    # Sorting on the source location makes "first" mean "earliest in the
    # codebase, by path then line" instead of "whichever fiber won".
    ordered_endpoints = endpoints.sort_by { |endpoint| endpoint_order_key(endpoint) }

    ordered_endpoints.each do |endpoint|
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

      # Drop param names that cannot be sent as-is: one containing a space,
      # and one that is blank. A blank name renders as `--cookie '='` in the
      # curl builder, an empty `└──` node in plain output and a
      # `{"name": ""}` entry that makes the OAS document invalid, so an
      # analyzer that knows a param exists but not what it is called must
      # not leak that hole into the report.
      #
      # Repeats of the same (name, param_type) are collapsed here too,
      # first-wins. `Endpoint#push_param`, `merge_params` and the graphql
      # merges all dedup on that key, and `params_to_hash` / `Endpoint#==`
      # collapse on it unconditionally — but an analyzer that appends
      # straight to `params` bypasses every one of those, and the duplicate
      # then reaches the report. It renders as two conflicting values for one
      # field (`-H 'Host: a' -H 'Host: b'`), which is not a request any
      # server can answer. Deduping here makes the emitted list agree with
      # what every consumer already computes from it.
      if endpoint.params.present?
        tiny_tmp.params = [] of Param
        seen_params = Set(Tuple(String, String)).new
        endpoint.params.each do |param|
          next if param.name.includes?(" ") || param.name.blank?
          next unless seen_params.add?({param.name, param.param_type})
          param.value = apply_pvalue(param.param_type, param.name, param.value).to_s
          tiny_tmp.params << param
        end
      end

      # An endpoint with no URL is not addressable, so it cannot be reported.
      # But reaching here means an analyzer or a path-composition helper
      # produced one, which is a bug upstream rather than something to
      # swallow: `join_trimmed` returning `""` for a root-mounted prefix hid
      # exactly that for every root-mapped JAX-RS / http4k / Micronaut /
      # Elysia / AdonisJS route. Debug level so normal runs stay quiet.
      if tiny_tmp.url.empty?
        @logger.debug_sub "  - Dropping endpoint with an empty URL: '#{tiny_tmp.method}' (#{tiny_tmp.details.technology || "unknown"})"
        next
      end

      # Duplicate check
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
          dup = merge_graphql_params(dup, tiny_tmp)
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
        dup = promote_scalar_context(dup, tiny_tmp)
        final_map[key] = dup
      else
        final_map[key] = tiny_tmp
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
      target = merge_graphql_params(target, source)
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

  # Carry the losing duplicate's scalar fields onto the winner.
  #
  # The dedup merges four collections (params, tags, callees, code_paths) and
  # used to discard everything else the loser knew. Which of two endpoints
  # with the same `(method, url, scope)` wins is decided by source location,
  # so the facts below were kept or lost depending on which file happened to
  # sort first:
  #
  # - `protocol`: ~20 analyzers set `ws` on endpoints that also have an
  #   ordinary HTTP path (`python/fastapi.cr`, `python/starlette.cr`,
  #   `java/spring.cr`, `elixir/phoenix_channel.cr`, …). `WebsocketTagger`
  #   keys off exactly this field and the taggers run *after* the optimizer,
  #   so losing it dropped the `websocket` tag from the report.
  # - `metadata`: the mobile deep-link facts (action/category/host/package).
  # - `details.status_code`: recorded by spec/capture-derived analyzers.
  # - `kind`: Next.js marks server actions here; the plain report prints it.
  #
  # `internal` moves the other way. It means "the app declares this request,
  # it does not serve it" (`@FeignClient` / `@HttpExchange`), and `Deliver`
  # reads it to skip probing. Another analyzer finding a real served route at
  # the same address contradicts that, so the merge clears the flag instead
  # of OR-ing it — otherwise a probe of a genuine endpoint would be
  # suppressed by whichever declaration sorted first.
  #
  # Returns the endpoint: `Endpoint` is a struct, so these writes land on a
  # copy unless the caller assigns the result back.
  private def promote_scalar_context(target : Endpoint, source : Endpoint) : Endpoint
    target.protocol = source.protocol if target.protocol == "http" && source.protocol != "http"
    target.metadata = source.metadata if target.metadata.nil?
    target.kind = source.kind if target.kind.empty?
    target.internal = false if target.internal && !source.internal

    if target.details.status_code.nil? && (status_code = source.details.status_code)
      details = target.details
      details.status_code = status_code
      target.details = details
    end

    target
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

  # Get allowed HTTP methods. AsyncAPI verbs (`PUBLISH`, `SUBSCRIBE`,
  # `SEND`, `RECEIVE`) ride along so the optimizer leaves event-driven
  # endpoints alone — DAST consumers route on these, and downgrading
  # them to `GET` would collapse publish + subscribe into one row.
  private def get_allowed_methods : Array(String)
    ALLOWED_HTTP_METHODS + SYNTHETIC_ENDPOINT_METHODS
  end
end
