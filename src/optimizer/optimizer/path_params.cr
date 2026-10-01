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
      url = endpoint.url
      placeholders = [] of PathPlaceholder

      # `{param}` patterns. A placeholder may sit at a segment boundary
      # (`/{id}`) or share a segment with literal separators
      # (`/{slug}_{pk}`, `/{name}.json`, `/{x},{y}`). Scan all brace
      # placeholders in the URL instead of assuming the preceding
      # character is `/` or `,`. Braces are matched by depth, so a regex
      # constraint's own quantifier (`{id:[0-9]{3}}`) stays inside the
      # placeholder instead of closing it early.
      each_brace_group(url) do |start, stop, raw|
        # Strip a leading `*` from catch-all path variables (Spring,
        # Armeria and ASP.NET all spell the rest-of-path capture as
        # `{*name}`, e.g. `/files/{*path}`) and any inline regex/type
        # constraint after `:`. The parameter is named `name`, not
        # `*name` or `name:regex`.
        param = raw.split(":")[0].lstrip('*')
        next unless valid_path_param_name?(param)
        placeholders << PathPlaceholder.new(start, stop, param)
      end

      # `/:param` patterns.
      url.scan(COLON_SEGMENT_RE) do |match|
        collect_colon_placeholders(match, placeholders)
      end

      # `<param>` patterns (Django / Flask / Marten / Bottle style).
      url.scan(ANGLE_PLACEHOLDER_RE) do |match|
        param = angle_bracket_param(match[1], endpoint)
        # Skip regex fragments. Play declares constrained path params as
        # `$name<regex>`, so the framework analyzer already recorded
        # `name`; the `<regex>` body (e.g. `\w{8}`, `[\w-]{2,6}`) is not
        # a param name.
        next unless valid_path_param_name?(param)
        placeholders << PathPlaceholder.new(match.byte_begin(0), match.byte_end(0), param)
      end

      # `/*param` patterns (wildcard / glob).
      url.scan(SPLAT_SEGMENT_RE) do |match|
        raw = match[1]
        # Only named splats are parameters (`/files/*path` -> `path`).
        # A bare glob like Armeria's `glob:/glob/**` captures `*`, and
        # a gRPC resource template leaves a trailing `}` — neither is a
        # real parameter name.
        next unless valid_path_param_name?(raw)
        placeholders << PathPlaceholder.new(match.byte_begin(1) - 1, match.byte_end(0), raw)
      end

      new_endpoint.url = register_path_params(url, new_endpoint.params, placeholders)

      reconcile_ruby_path_params(new_endpoint)

      final << new_endpoint
    end

    final
  end

  # One path-parameter placeholder found in a URL: the byte span it occupies
  # (`:id`, `{id:\d+}`, `<int:id>`, `*path`) and the param name it declares.
  private record PathPlaceholder, start : Int32, stop : Int32, name : String

  COLON_SEGMENT_RE     = /\/:([^\/{}]+)/
  ANGLE_PLACEHOLDER_RE = /<([^>]+)>/
  SPLAT_SEGMENT_RE     = /\/\*([^\/]+)/

  # A `:name` param name. Hyphens are part of the identifier — kebab-case
  # path params are idiomatic in Clojure (`/:artifact-id`, `/:group-id`) and
  # legal in several other route DSLs. Excluding `-` truncated `artifact-id`
  # to `artifact`. A hyphen only joins the name when an identifier character
  # follows it, though: Express's `/:from-:to` declares `from` and `to`
  # around a literal `-`, not a param named `from-`.
  PATH_PARAM_IDENT_RE = /\A[A-Za-z_][A-Za-z0-9_]*(?:-[A-Za-z0-9_]+)*/

  # Record each placeholder's param (deduped by name) and substitute a
  # configured path-param value for it when one is set. Returns the updated
  # URL; `params` is mutated in place — it is the endpoint's own array
  # reference, so the push persists on the caller's struct.
  #
  # Substitution rewrites the exact byte span each placeholder was found at.
  # A textual `gsub(placeholder, value)` was substring-unsafe: replacing
  # `:id` also rewrote the head of `:identifier` (`/users/7/files/7entifier`),
  # and the greedy `:id-:idx` capture swallowed the second param whole.
  private def register_path_params(url : String, params : Array(Param), placeholders : Array(PathPlaceholder)) : String
    return url if placeholders.empty?

    values = {} of String => String
    placeholders.each do |placeholder|
      name = placeholder.name
      value = values[name] ||= apply_pvalue("path", name, "")
      # Carry the configured value like every other param kind does, so the
      # param agrees with what was substituted into the URL.
      params << Param.new(name, value, "path") unless path_param_present?(params, name)
    end
    return url if values.each_value.all?(&.empty?)

    String.build do |io|
      cursor = 0
      placeholders.sort_by(&.start).each do |placeholder|
        # Spans from different passes only overlap on malformed input (a
        # `<...>` inside a `{...}`); the earlier one wins.
        next if placeholder.start < cursor
        value = values[placeholder.name]
        next if value.empty?
        io << url.byte_slice(cursor, placeholder.start - cursor) << value
        cursor = placeholder.stop
      end
      io << url.byte_slice(cursor, url.bytesize - cursor)
    end
  end

  # Collect the `:name` placeholders in one `/:...` segment match. Besides
  # the leading name, a segment may carry an Express regex constraint
  # (`/:id(\\d+)`) and an optional/repeat modifier (`/:ip?`, `/:path*`),
  # which belong to the placeholder, and further params joined by `-` or `.`
  # (`/:from-:to`, `/:genus.:species`). Anything else that follows — Play's
  # `/:lang.json` format suffix — is literal text and stays in the URL.
  private def collect_colon_placeholders(match : Regex::MatchData, placeholders : Array(PathPlaceholder)) : Nil
    raw = match[1]
    base = match.byte_begin(1)
    bytes = raw.to_slice
    pos = 0

    while ident = raw.byte_slice(pos, bytes.size - pos).match(PATH_PARAM_IDENT_RE)
      name = ident[0]
      stop = pos + name.bytesize
      stop = skip_paren_group(bytes, stop) if stop < bytes.size && '(' === bytes[stop]
      stop += 1 if stop < bytes.size && ('?' === bytes[stop] || '*' === bytes[stop] || '+' === bytes[stop])
      placeholders << PathPlaceholder.new(base + pos - 1, base + stop, name)

      break unless stop + 1 < bytes.size && ('-' === bytes[stop] || '.' === bytes[stop]) && ':' === bytes[stop + 1]
      pos = stop + 2
    end
  end

  # Index just past the `)` closing the group that opens at `start`, or
  # `start` itself when the group is unbalanced.
  private def skip_paren_group(bytes : Bytes, start : Int32) : Int32
    depth = 0
    i = start
    while i < bytes.size
      byte = bytes[i]
      if '\\' === byte
        i += 2
        next
      elsif '(' === byte
        depth += 1
      elsif ')' === byte
        depth -= 1
        return i + 1 if depth == 0
      end
      i += 1
    end
    start
  end

  # Converter names that can lead a `<converter:name>` placeholder. Same list
  # as `OutputBuilderOasCommon::PATH_CONVERTER_TYPES`, so the two resolve a
  # placeholder the same way.
  ANGLE_CONVERTER_TYPES = Set{"int", "str", "string", "slug", "uuid", "float", "bool", "path", "any"}

  # Frameworks whose `<...>` placeholders are always converter first: Django
  # `path()` (`<int:pk>`) and Werkzeug-routed Flask/Quart (`<int:id>`). Their
  # converters are user-extensible (`register_converter(..., "yyyy")`,
  # `app.url_map.converters`), so the builtin list alone can't recognize a
  # custom one; `<yyyy:year>` declares `year`, not `yyyy`.
  CONVERTER_FIRST_TECHS = Set{"python_django", "python_flask", "python_quart"}

  # Werkzeug converter arguments: `int(signed=True)`, `any(about, help)`.
  CONVERTER_ARGS_RE = /\([^()]*\)/

  # Resolve the param name from a `<...>` capture, handling both converter-
  # first `<type:name>` (Django, Flask) and name-first `<name:type>` (Marten,
  # Sanic, Bottle, Mojolicious, Plumber) ordering. Converter arguments are
  # not part of the converter name — `<int(signed=True):num>` used to fail
  # the builtin check and resolve to the whole `int(signed=True)` — so they
  # are dropped before splitting.
  private def angle_bracket_param(raw : String, endpoint : Endpoint) : String
    raw = raw.gsub(CONVERTER_ARGS_RE, "") if raw.includes?('(')
    parts = raw.split(":")
    return parts[0] if parts.size <= 1

    head = parts[0]
    tail = parts[1]
    # A path param the analyzer already recorded settles the order.
    return head if path_param_present?(endpoint.params, head)
    return tail if path_param_present?(endpoint.params, tail)
    return tail if CONVERTER_FIRST_TECHS.includes?(endpoint.details.technology)
    ANGLE_CONVERTER_TYPES.includes?(head) ? tail : head
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
end
