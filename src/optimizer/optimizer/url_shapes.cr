# Part of EndpointOptimizer: regex-route URL shape normalization (anchors, named
# capture groups, colon segments).
class EndpointOptimizer
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
      endpoint.url = normalize_url_shape(endpoint.url, technology: endpoint.details.technology)
      endpoints[idx] = endpoint
    end

    endpoints
  end

  private def normalize_url_shape(url : String, normalize_colon_segments : Bool = false, technology : String? = nil) : String
    return url if url.empty?

    # Skip URLs that look like a verbatim regex literal — Express
    # accepts `app.get(/^\/api\/(\d+)$/, handler)` and the route
    # extractor preserves the literal as the URL. The unique signal is
    # escaped slashes (`\/`).
    return url if url.includes?("\\/")

    normalized = url

    # Regex named groups: `(?P<name>...)` / `(?<name>...)` → `{name}`.
    normalized = strip_named_capture_groups(normalized)

    # Spring `{name:regex}` path variables — strip the inline regex
    # constraint so downstream consumers see the canonical placeholder.
    normalized = strip_brace_constraints(normalized)

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

    # Strip regex anchors at the path boundary. Grape accepts a literal `$`
    # at the end of a route, so only that ambiguous suffix is technology-gated.
    normalized = normalized.sub(/^\/\^/, "/")
    normalized = normalized.sub(/\$$/, "") unless technology == "ruby_grape"
    normalized = normalized.sub(/\\Z$/, "")
    normalized = normalized.sub(/\/\$$/, "/")

    # Backslash-escaped dots (Python re_path `r"\.json"`) → literal dot.
    normalized = normalized.gsub("\\.", ".")

    # Final path double-slash collapse in case the rewrites left an
    # adjacent pair. Skip absolute URLs entirely; the `//` after the
    # scheme is structural, not a path separator.
    normalized = collapse_path_slashes(normalized) unless normalized.matches?(ABSOLUTE_URL_RE)

    normalized
  end

  BRACE_CONSTRAINT_RE = /\A([A-Za-z_][A-Za-z0-9_]*):./

  # Rewrites `{name:regex}` to `{name}`. The constraint may itself contain
  # braces — a quantifier (`{id:[0-9]{3}}`, `{code:\d{5}}`) — which a flat
  # `\{name:[^{}]+\}` pattern could never match, so such a placeholder used
  # to reach every report with its regex intact.
  private def strip_brace_constraints(url : String) : String
    return url unless url.includes?('{')

    cursor = 0
    result = String.build do |io|
      each_brace_group(url) do |start, stop, inner|
        next unless match = inner.match(BRACE_CONSTRAINT_RE)
        io << url.byte_slice(cursor, start - cursor) << '{' << match[1] << '}'
        cursor = stop
      end
      io << url.byte_slice(cursor, url.bytesize - cursor)
    end
    cursor == 0 ? url : result
  end

  # Yields the byte span (`start` inclusive, `stop` exclusive) and the inner
  # text of every top-level `{...}` group in `url`. Braces are matched by
  # depth and a backslash escapes the next byte, so a regex constraint's own
  # quantifier (`{id:[0-9]{3}}`) closes inside the group rather than ending
  # it at the first `}`. An unbalanced `{` is skipped. Shared by the
  # constraint strip above and `add_path_parameters`, so both agree on where
  # a placeholder ends.
  private def each_brace_group(url : String, & : Int32, Int32, String ->) : Nil
    return unless url.includes?('{')

    bytes = url.to_slice
    i = 0
    while i < bytes.size
      if '{' === bytes[i] && (close = matching_brace(bytes, i))
        yield i, close + 1, url.byte_slice(i + 1, close - i - 1)
        i = close + 1
      else
        i += 1
      end
    end
  end

  # Index of the `}` closing the `{` at `open`, or nil when it never closes.
  private def matching_brace(bytes : Bytes, open : Int32) : Int32?
    depth = 0
    i = open
    while i < bytes.size
      byte = bytes[i]
      if '\\' === byte
        i += 2
        next
      elsif '{' === byte
        depth += 1
      elsif '}' === byte
        depth -= 1
        return i if depth == 0
      end
      i += 1
    end
  end

  # Rewrites every named capture group in `url` to `{name}`, consuming the
  # matching `)` even when the inner pattern contains nested parens. Returns
  # `url` unchanged when no named group is present.
  #
  # Both spellings are handled. `(?P<name>…)` is Python's; `(?<name>…)` is
  # what Perl 5.10+, PCRE, .NET, Java, Ruby and JavaScript use, and it reached
  # reports raw — Dancer2's `get qr{/ticket/(?<code>[0-9]+)}` was emitted as
  # the literal URL `/ticket/(?<code>[0-9]+)` even though the analyzer had
  # already recorded `code` as a path param, so the endpoint's URL and its
  # parameter list disagreed.
  #
  # `(?<=` and `(?<!` are lookbehind assertions, not names, and are left alone.
  private def strip_named_capture_groups(url : String) : String
    return url unless url.includes?("(?P<") || url.includes?("(?<")

    result = String::Builder.new
    i = 0
    size = url.size
    while i < size
      name_start = named_group_name_start(url, i, size)
      if name_start
        close_name = url.index('>', name_start)
        unless close_name
          result << url[i..]
          break
        end
        name = url[name_start...close_name]

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

  # Index just past the opening delimiter of a named capture group starting at
  # `i` (i.e. where the name begins), or nil when `i` isn't one.
  private def named_group_name_start(url : String, i : Int32, size : Int32) : Int32?
    return unless i + 2 < size && url[i] == '(' && url[i + 1] == '?'

    if url[i + 2] == 'P' && i + 3 < size && url[i + 3] == '<'
      i + 4
    elsif url[i + 2] == '<' && i + 3 < size && url[i + 3] != '=' && url[i + 3] != '!'
      i + 3
    end
  end
end
