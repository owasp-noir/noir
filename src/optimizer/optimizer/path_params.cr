# Part of EndpointOptimizer: URL+endpoint combination and path-parameter extraction
# ({id}, :id, <int:id>, Ruby reconcile).
class EndpointOptimizer
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
      # not a path-parameter template. Realtime `ws://` event URLs are kept
      # verbatim too — a Phoenix topic like `ws://room:lobby/new_msg` carries
      # a literal `:lobby` that this pass would otherwise misread as an
      # Express-style `:name` path parameter. Mobile deep links are NOT
      # skipped here: their `myapp://host/:id` URLs legitimately carry path
      # params that this pass extracts.
      if endpoint.cli? || endpoint.realtime?
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
end
