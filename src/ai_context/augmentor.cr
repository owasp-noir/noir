require "../models/endpoint"

module NoirAIContext
  extend self

  def apply(endpoints : Array(Endpoint)) : Array(Endpoint)
    Builder.new.apply(endpoints)
  end

  private class PatternDefinition
    getter kind : String
    getter description : String
    getter confidence : Int32
    getter name_patterns : Array(Regex)
    getter source_patterns : Array(Regex)

    def initialize(@kind : String,
                   @description : String,
                   @confidence : Int32,
                   *,
                   @name_patterns : Array(Regex) = [] of Regex,
                   @source_patterns : Array(Regex) = [] of Regex)
    end
  end

  private class Builder
    ROUTE_SNIPPET_RADIUS  =   2
    SOURCE_SCAN_RADIUS    =   6
    CALLEE_SNIPPET_RADIUS =   1
    MAX_SNIPPET_CHARS     = 240
    MAX_ROUTE_SCOPE_LINES =  12

    STATE_CHANGING_METHODS = Set{"POST", "PUT", "PATCH", "DELETE"}
    BODY_LIKE_PARAM_TYPES  = Set{"json", "form"}

    SINK_PATTERNS = [
      PatternDefinition.new(
        "sql",
        "Potential SQL/data-store sink inferred from code or callee name",
        78,
        name_patterns: [/raw_?sql/i, /find_?by_?sql/i, /\bquery\b/i, /\bexecute\b/i, /\bselect\b/i],
        source_patterns: [/find_by_sql/i, /\braw(sql|_sql)\b/i, /\bselect\b.+\bfrom\b/i, /\bexecute(Query|Sql)?\b/i]
      ),
      PatternDefinition.new(
        "command_exec",
        "Potential command execution sink inferred from code or callee name",
        82,
        name_patterns: [/\bexec\b/i, /\bsystem\b/i, /\bspawn\b/i, /\bpopen\b/i, /\bshell\b/i],
        source_patterns: [/\bexec\s*\(/i, /\bsystem\s*\(/i, /\bspawn\s*\(/i, /\bpopen\s*\(/i, /ProcessBuilder/i, /Runtime\.getRuntime/i, /subprocess\./i]
      ),
      PatternDefinition.new(
        "file_io",
        "Potential file I/O sink inferred from code or callee name",
        68,
        name_patterns: [/\bfile\b/i, /\bread\b/i, /\bupload\b/i, /\bdownload\b/i],
        source_patterns: [/\bFile\.(open|read|write)/, /\bread(File|_text)\b/i, /\bwrite(File|_text)\b/i, /\bsend_file\b/i, /\bsendFile\b/i, /\bdownload\b/i, /\bupload\b/i]
      ),
      PatternDefinition.new(
        "redirect",
        "Potential redirect sink inferred from code or callee name",
        74,
        name_patterns: [/\bredirect\b/i, /\bredirect_to\b/i],
        source_patterns: [/\bredirect(_to)?\s*\(/i, /\bres\.redirect\b/i, /Response\.Redirect/i]
      ),
      PatternDefinition.new(
        "template_render",
        "Potential template/render sink inferred from code or callee name",
        62,
        name_patterns: [/\brender\b/i, /\btemplate\b/i, /\bhtml\b/i, /\brespond\b/i],
        source_patterns: [/\brender(_template)?\s*\(/i, /\breturn\s+render\b/i, /\brespond_to\b/i]
      ),
      PatternDefinition.new(
        "outbound_http",
        "Potential outbound HTTP/client sink inferred from code or callee name",
        64,
        name_patterns: [/\bhttp\b/i, /\bfetch\b/i, /\bclient\b/i, /\baxios\b/i],
        source_patterns: [/requests\.(get|post|put|delete)/i, /\bfetch\s*\(/i, /\baxios\./i, /\bhttp\.(Get|Post|NewRequest)/, /\bclient\.(get|post|request)/i]
      ),
    ] of PatternDefinition

    VALIDATOR_PATTERNS = [
      PatternDefinition.new(
        "validation",
        "Potential validation step inferred from code or callee name",
        64,
        name_patterns: [/\bvalidate\b/i, /\bvalidator\b/i, /\bverify\b/i, /\bpermit\b/i],
        source_patterns: [/\bvalidate\w*\s*\(/i, /\bvalidator\b/i, /\bpermit\s*\(/i, /\bverify\w*\s*\(/i]
      ),
      PatternDefinition.new(
        "sanitization",
        "Potential sanitization or escaping step inferred from code or callee name",
        68,
        name_patterns: [/\bsanitize\b/i, /\bescape\b/i, /\bencode\b/i, /\bnormalize\b/i, /\bclean\b/i],
        source_patterns: [/\bsanitize\w*\s*\(/i, /\bescape\w*\s*\(/i, /\bhtml_escape\b/i, /\bnormalize\w*\s*\(/i, /\bclean\w*\s*\(/i]
      ),
    ] of PatternDefinition

    GUARD_PATTERNS = [
      PatternDefinition.new(
        "guard",
        "Potential authz/authn guard inferred from nearby source",
        52,
        source_patterns: [
          /passport\.authenticate/i,
          /expressjwt/i,
          /\bauthenticate\w*\b/i,
          /\bauthorize\w*\b/i,
          /\brequireAuth\b/i,
          /\bverifyToken\b/i,
          /\bcheckPermission\b/i,
          /Depends\s*\(\s*get_current_/i,
          /Security\s*\(/i,
          /before_action\s+:\w*auth/i,
          /\.Use\s*\(\s*\w*Auth\w*/i,
        ]
      ),
    ] of PatternDefinition

    PARAM_PATTERNS = [
      PatternDefinition.new(
        "credential_input",
        "Credential-bearing input; review secret handling, logging, and auth bypass paths",
        86,
        name_patterns: [/\b(pass(word)?|token|secret|api[_-]?key|authorization|session|cookie|jwt|bearer)\b/i]
      ),
      PatternDefinition.new(
        "identifier_input",
        "Identifier-like input frequently drives authorization and object lookup decisions",
        74,
        name_patterns: [/\bid\b/i, /\buser(_id)?\b/i, /\baccount(_id)?\b/i, /\border(_id)?\b/i, /\bprofile\b/i, /\bdoc(ument)?\b/i, /\bproject(_id)?\b/i]
      ),
      PatternDefinition.new(
        "redirect_input",
        "Redirect or callback-like input may affect navigation or outbound requests",
        76,
        name_patterns: [/\b(url|uri|redirect|return|next|continue|dest|destination|callback)\b/i]
      ),
      PatternDefinition.new(
        "file_input",
        "File-like input may influence upload, download, or path traversal behavior",
        78,
        name_patterns: [/\b(file|upload|attachment|image|document|filename|filepath|path)\b/i]
      ),
      PatternDefinition.new(
        "query_builder_input",
        "Query-builder-like input can influence filtering, sorting, or data access clauses",
        70,
        name_patterns: [/\b(sort|order|filter|where|search|select|field|column)\b/i]
      ),
    ] of PatternDefinition

    @file_cache : Hash(String, Array(String))

    def initialize
      @file_cache = {} of String => Array(String)
    end

    def apply(endpoints : Array(Endpoint)) : Array(Endpoint)
      endpoints.map! do |endpoint|
        context = build_context(endpoint)
        endpoint.ai_context = context.empty? ? nil : context
        endpoint
      end

      endpoints
    end

    private def build_context(endpoint : Endpoint) : AIContext
      context = AIContext.new
      anchor = endpoint.details.code_paths.first?
      route_snippet = snippet_for(anchor.try(&.path), anchor.try(&.line), ROUTE_SNIPPET_RADIUS)

      add_route_signal(context, endpoint, anchor, route_snippet)
      add_technology_signal(context, endpoint, anchor, route_snippet)
      add_method_signal(context, endpoint, anchor, route_snippet)
      add_internal_signal(context, endpoint, anchor, route_snippet)
      add_param_signals(context, endpoint, anchor, route_snippet)
      add_tag_entries(context, endpoint, anchor, route_snippet)
      add_callee_entries(context, endpoint)
      add_source_scan_entries(context, endpoint)
      add_missing_guard_signal(context, endpoint, anchor, route_snippet)

      context
    end

    private def add_route_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      context.push_signal(AIContextEntry.new(
        "route_definition",
        "#{endpoint.method} #{endpoint.url}",
        source: "route",
        description: "Primary route registration or controller entrypoint",
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: 100,
        snippet: route_snippet
      ))
    end

    private def add_technology_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless technology = endpoint.details.technology

      context.push_signal(AIContextEntry.new(
        "technology",
        technology,
        source: "detector",
        description: "Detected framework or language technology for this endpoint",
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: 96,
        snippet: route_snippet
      ))
    end

    private def add_method_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless STATE_CHANGING_METHODS.includes?(endpoint.method)

      description = case endpoint.method
                    when "DELETE"
                      "State-changing delete endpoint; review authorization, ownership, and destructive side effects"
                    else
                      "State-changing endpoint; review authz, validation, and side effects"
                    end

      context.push_signal(AIContextEntry.new(
        "state_change",
        endpoint.method,
        source: "http_method",
        description: description,
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: 88,
        snippet: route_snippet
      ))
    end

    private def add_internal_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless endpoint.internal

      context.push_signal(AIContextEntry.new(
        "internal_endpoint",
        "#{endpoint.method} #{endpoint.url}",
        source: "endpoint",
        description: "Analyzer marked this endpoint as internal-only or non-public",
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: 78,
        snippet: route_snippet
      ))
    end

    private def add_param_signals(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      endpoint.params.each do |param|
        add_path_param_signal(context, param, anchor, route_snippet)

        PARAM_PATTERNS.each do |pattern|
          next unless matches_any?(param.name, pattern.name_patterns)
          next if skip_param_signal?(endpoint, param, pattern)
          next if redundant_param_signal?(param, pattern)

          description = if param.param_type == "path" && pattern.kind == "identifier_input"
                          "Path parameter selects a server-side resource; review authorization and ownership checks"
                        else
                          pattern.description
                        end

          context.push_signal(AIContextEntry.new(
            pattern.kind,
            "#{param.param_type}.#{param.name}",
            source: "param",
            description: description,
            path: anchor.try(&.path),
            line: anchor.try(&.line),
            confidence: pattern.confidence,
            snippet: route_snippet
          ))
        end

        param.tags.each do |tag|
          context.push_signal(AIContextEntry.new(
            tag.name,
            "#{param.param_type}.#{param.name}",
            source: "param_tagger:#{tag.tagger}",
            description: "#{tag.description} Matched by parameter-name heuristic.",
            path: anchor.try(&.path),
            line: anchor.try(&.line),
            confidence: 58,
            snippet: route_snippet
          ))
        end
      end
    end

    private def skip_param_signal?(endpoint : Endpoint, param : Param, pattern : PatternDefinition) : Bool
      return false unless pattern.kind == "identifier_input"
      return !header_identifier_like?(param.name) if param.param_type == "header"
      return false unless BODY_LIKE_PARAM_TYPES.includes?(param.param_type)
      param.name == "id"
    end

    private def redundant_param_signal?(param : Param, pattern : PatternDefinition) : Bool
      case pattern.kind
      when "query_builder_input"
        param.tags.any? { |tag| tag.name == "sqli" }
      when "identifier_input"
        param.param_type == "path" && param.tags.any? { |tag| tag.name == "idor" }
      else
        false
      end
    end

    private def add_path_param_signal(context : AIContext, param : Param, anchor : PathInfo?, route_snippet : String?)
      return unless param.param_type == "path"

      context.push_signal(AIContextEntry.new(
        "path_param",
        param.name,
        source: "param",
        description: "Path parameter participates in route selection and often controls object lookup",
        path: anchor.try(&.path),
        line: anchor.try(&.line),
        confidence: 84,
        snippet: route_snippet
      ))
    end

    private def add_tag_entries(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      endpoint.tags.each do |tag|
        entry = AIContextEntry.new(
          guard_tag?(tag) ? "auth_guard" : tag.name,
          guard_tag?(tag) ? guard_name_from_tag(tag) : tag.name,
          source: tag.tagger,
          description: tag.description,
          path: anchor.try(&.path),
          line: anchor.try(&.line),
          confidence: tag.name == "auth" ? 86 : 74,
          snippet: route_snippet
        )

        if guard_tag?(tag)
          context.push_guard(entry)
        else
          context.push_signal(entry)
          if tag.name == "file_upload"
            context.push_sink(AIContextEntry.new(
              "file_io",
              "file_upload",
              source: tag.tagger,
              description: "Endpoint characteristics suggest file upload or file handling behavior",
              path: anchor.try(&.path),
              line: anchor.try(&.line),
              confidence: 80,
              snippet: route_snippet
            ))
          end
        end
      end
    end

    private def add_callee_entries(context : AIContext, endpoint : Endpoint)
      endpoint.callees.each do |callee|
        callee_snippet = snippet_for(callee.path, callee.line, CALLEE_SNIPPET_RADIUS)

        context.push_callee(AIContextEntry.new(
          "callee",
          callee.name,
          source: "callee",
          description: "Direct 1-hop handler callee extracted from the endpoint body",
          path: callee.path,
          line: callee.line,
          confidence: 92,
          snippet: callee_snippet
        ))

        if sink = detect_from_patterns(callee.name, callee_snippet, SINK_PATTERNS, callee.path, callee.line, "callee")
          context.push_sink(sink)
        end

        if validator = detect_from_patterns(callee.name, callee_snippet, VALIDATOR_PATTERNS, callee.path, callee.line, "callee")
          context.push_validator(validator)
        end
      end
    end

    private def add_source_scan_entries(context : AIContext, endpoint : Endpoint)
      return if endpoint.details.code_paths.empty?

      endpoint.details.code_paths.each do |path_info|
        route_scope = route_scope_snippet_for(path_info.path, path_info.line)

        if context.guards.empty?
          if guard = detect_from_patterns("", route_scope, GUARD_PATTERNS, path_info.path, path_info.line, "route_source")
            context.push_guard(guard)
          end
        end

        snippet = route_scope || snippet_for(path_info.path, path_info.line, SOURCE_SCAN_RADIUS)
        next if snippet.nil?

        if context.sinks.empty?
          if sink = detect_from_patterns("", snippet, SINK_PATTERNS, path_info.path, path_info.line, "route_source")
            context.push_sink(sink)
          end
        end

        if context.validators.empty?
          if validator = detect_from_patterns("", snippet, VALIDATOR_PATTERNS, path_info.path, path_info.line, "route_source")
            context.push_validator(validator)
          end
        end
      end
    end

    private def add_missing_guard_signal(context : AIContext, endpoint : Endpoint, anchor : PathInfo?, route_snippet : String?)
      return unless STATE_CHANGING_METHODS.includes?(endpoint.method)
      return unless context.guards.empty?

      if endpoint.params.any? { |param| param.param_type == "path" && identifier_like?(param.name) }
        context.push_signal(AIContextEntry.new(
          "idor_review",
          endpoint.url,
          source: "heuristic",
          description: "State-changing endpoint uses path identifiers without a detected guard; review object-level authorization carefully.",
          path: anchor.try(&.path),
          line: anchor.try(&.line),
          confidence: 36,
          snippet: route_snippet
        ))
      else
        context.push_signal(AIContextEntry.new(
          "guard_absence",
          endpoint.method,
          source: "heuristic",
          description: "No auth guard was detected for this state-changing endpoint. This may be real or a heuristic blind spot; review manually.",
          path: anchor.try(&.path),
          line: anchor.try(&.line),
          confidence: 28,
          snippet: route_snippet
        ))
      end
    end

    private def guard_tag?(tag : Tag) : Bool
      return true if tag.name == "auth"
      tag.tagger.downcase.ends_with?("_auth")
    end

    private def guard_name_from_tag(tag : Tag) : String
      description = tag.description
      return description.sub(/^Protected by\s+/, "") if description.starts_with?("Protected by ")
      tag.name
    end

    private def detect_from_patterns(name : String,
                                     snippet : String?,
                                     patterns : Array(PatternDefinition),
                                     path : String?,
                                     line : Int32?,
                                     source : String) : AIContextEntry?
      patterns.each do |pattern|
        next if suppress_pattern_detection?(pattern.kind, name, snippet)

        name_match = name_match_text(name, pattern.name_patterns)
        snippet_match = snippet_match_text(snippet, pattern.source_patterns)
        next unless name_match || snippet_match
        next if source == "callee" && name_match.nil?

        evidence_name = name_match || snippet_match || pattern.kind
        return AIContextEntry.new(
          pattern.kind,
          evidence_name,
          source: source,
          description: pattern.description,
          path: path,
          line: line,
          confidence: source == "route_source" ? pattern.confidence - 12 : pattern.confidence,
          snippet: snippet
        )
      end

      nil
    end

    private def suppress_pattern_detection?(kind : String, name : String, snippet : String?) : Bool
      case kind
      when "sql"
        return true if name.matches?(/\b(URL\.Query|QueryParam|request\.query|req\.query|query_params|searchParams)\b/i)
        return true if snippet && snippet.matches?(/\b(URL\.Query\(\)\.Get|QueryParam\(|request\.query\.|req\.query\.|searchParams\.get)\b/i)
      when "template_render"
        return false unless snippet
        return true if snippet.matches?(/\brender\s+(json|plain|xml|body|status):/i)
        return true if snippet.matches?(/\brespond(Text|Bytes|File|Json|Redirect)\b/)
      when "outbound_http"
        return true if name.starts_with?("request.")
        return true if name == "request"
      end

      false
    end

    private def name_match_text(name : String, patterns : Array(Regex)) : String?
      return if name.empty?

      patterns.each do |pattern|
        if match = name.match(pattern)
          return normalize_label(match[0])
        end
      end

      nil
    end

    private def snippet_match_text(snippet : String?, patterns : Array(Regex)) : String?
      return unless snippet

      patterns.each do |pattern|
        if match = snippet.match(pattern)
          return normalize_label(match[0])
        end
      end

      nil
    end

    private def matches_any?(name : String, patterns : Array(Regex)) : Bool
      patterns.any? { |pattern| name.matches?(pattern) }
    end

    private def identifier_like?(name : String) : Bool
      return true if matches_any?(name, PARAM_PATTERNS.find { |pattern| pattern.kind == "identifier_input" }.not_nil!.name_patterns)
      return true if identifier_suffix_like?(name)

      false
    end

    private def header_identifier_like?(name : String) : Bool
      normalized = name.downcase
      return true if normalized.matches?(/\b[a-z0-9_-]*id\b/)
      return true if normalized.matches?(/\b(client|account|order|profile|project|merchant|store|user)[_-]?id\b/)

      false
    end

    private def identifier_suffix_like?(name : String) : Bool
      return true if name == "id"
      return true if name.matches?(/[_-]id$/i)
      return true if name.matches?(/[a-z0-9]Id$/)
      return true if name.matches?(/[a-z0-9]ID$/)

      false
    end

    private def normalize_label(text : String) : String
      text.gsub(/\s+/, " ").strip[0, Math.min(text.gsub(/\s+/, " ").strip.size, 64)]
    end

    private def snippet_for(path : String?, line : Int32?, radius : Int32) : String?
      return unless path && line

      lines = read_lines(path)
      return if line < 1 || line > lines.size

      start_idx = Math.max(line - radius - 1, 0)
      end_idx = Math.min(line + radius - 1, lines.size - 1)
      selected = [] of String

      (start_idx..end_idx).each do |idx|
        selected << "#{idx + 1}: #{lines[idx].strip}"
      end

      snippet = selected.join(" | ").gsub(/\s+/, " ").strip
      return if snippet.empty?
      snippet.size > MAX_SNIPPET_CHARS ? snippet[0, MAX_SNIPPET_CHARS] : snippet
    end

    private def route_scope_snippet_for(path : String?, line : Int32?) : String?
      return unless path && line

      lines = read_lines(path)
      return if line < 1 || line > lines.size

      start_idx = line - 1
      selected = [] of String
      brace_depth = 0
      seen_block = false
      paren_balance = 0

      start_idx.upto(Math.min(start_idx + MAX_ROUTE_SCOPE_LINES - 1, lines.size - 1)) do |idx|
        raw_line = lines[idx]
        selected << "#{idx + 1}: #{raw_line.strip}"

        sanitized = raw_line.gsub(/(['"]).*?\1/, "\"\"")
        opens = sanitized.count('{')
        closes = sanitized.count('}')
        brace_depth += opens - closes
        paren_balance += sanitized.count('(') - sanitized.count(')')

        seen_block ||= opens > 0 || sanitized.matches?(/\bdo\b/)

        if seen_block
          break if brace_depth <= 0
        else
          stripped = sanitized.strip
          statement_done = stripped.ends_with?(";") || stripped.ends_with?(")") || stripped.ends_with?(" do")
          break if statement_done && paren_balance <= 0
        end
      end

      snippet = selected.join(" | ").gsub(/\s+/, " ").strip
      return if snippet.empty?
      snippet.size > MAX_SNIPPET_CHARS ? snippet[0, MAX_SNIPPET_CHARS] : snippet
    end

    private def read_lines(path : String) : Array(String)
      if cached = @file_cache[path]?
        return cached
      end

      lines = File.read(path, encoding: "utf-8", invalid: :skip).split("\n")
      @file_cache[path] = lines
      lines
    rescue
      [] of String
    end
  end
end
