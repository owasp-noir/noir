require "../../../models/analyzer"
require "../../../miniparsers/haskell_callee_extractor"
require "set"

module Analyzer::Haskell
  class Servant < Analyzer
    HTTP_METHOD_VERBS = %w[GET POST PUT DELETE PATCH OPTIONS HEAD]

    alias TypeAlias = NamedTuple(body: String, source: String, line: Int32)
    alias TypeAliasKey = Tuple(String, String)
    alias TypeAliasIndex = Hash(TypeAliasKey, TypeAlias)
    alias HandlerBody = Noir::HaskellCalleeExtractor::FunctionBody
    alias HandlerKey = Tuple(String, String)
    alias HandlerBodies = Hash(HandlerKey, Array(HandlerBody))
    alias ServerBindings = Hash(Tuple(String, String), String)

    def analyze
      type_aliases = TypeAliasIndex.new
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      handler_bodies = include_callee ? build_handler_bodies : HandlerBodies.new
      server_bindings = include_callee ? build_server_bindings : ServerBindings.new

      all_files.each do |path|
        next if File.directory?(path)
        next unless haskell_source?(path)

        content = read_file_content(path)
        base_path = configured_base_for(path)
        extract_type_aliases(content).each do |entry|
          type_aliases[{base_path, entry[:name]}] = {
            body:   entry[:body],
            source: path,
            line:   entry[:line],
          }
        end

        # Record-based (`NamedRoutes`) APIs declare each route as a record field
        # `field :: mode :- <route>`. Treat the record as a pseudo type alias
        # whose body is the fields joined with `:<|>`, so the existing
        # expansion/processing pipeline handles it like any other API.
        extract_record_routes(content).each do |entry|
          type_aliases[{base_path, entry[:name]}] = {
            body:   entry[:body],
            source: path,
            line:   entry[:line],
          }
        end
      end

      reference_counts = Hash(TypeAliasKey, Int32).new(0)
      type_aliases.each do |key, entry|
        base_path = key[0]
        referenced_aliases(entry[:body], alias_names_for_base(type_aliases, base_path)).each do |name|
          reference_counts[{base_path, name}] += 1
        end
      end

      type_aliases.each do |key, entry|
        base_path, name = key
        next if reference_counts[key] > 0

        expanded = strip_named_routes(expand_references(entry[:body], type_aliases, base_path))
        next unless contains_servant_signature?(expanded)

        endpoints = process_api_body(entry[:source], entry[:line], expanded)
        attach_servant_callees(name, entry[:source], endpoints, handler_bodies, server_bindings) if include_callee
        @result.concat(endpoints)
      end

      @result
    end

    private def build_handler_bodies : HandlerBodies
      handlers = HandlerBodies.new

      all_files.each do |path|
        next if File.directory?(path)
        next unless haskell_source?(path)

        Noir::HaskellCalleeExtractor.function_bodies(read_file_content(path), path).each do |body|
          key = handler_key(configured_base_for(path), body[:name])
          handlers[key] ||= [] of HandlerBody
          handlers[key] << body
        end
      end

      handlers
    end

    private def handler_key(base_path : String, name : String) : HandlerKey
      {base_path, name}
    end

    private def build_server_bindings : ServerBindings
      bindings = ServerBindings.new

      all_files.each do |path|
        next if File.directory?(path)
        next unless haskell_source?(path)

        extract_server_binding_targets(read_file_content(path)).each do |entry|
          bindings[{path, entry[:name]}] = entry[:target]
        end
      end

      bindings
    end

    private def extract_server_binding_targets(content : String) : Array(NamedTuple(name: String, target: String))
      targets = [] of NamedTuple(name: String, target: String)
      cleaned = strip_haskell_comments(content)

      cleaned.each_line do |line|
        match = line.match(/^\s*([a-z_][A-Za-z0-9_']*)\s*::.*\bServer(?:T)?\b\s*(.*)$/)
        next unless match

        target_match = match[2].strip.match(/\A([A-Z][A-Za-z0-9_']*)\b/)
        targets << {
          name:   match[1],
          target: target_match ? target_match[1] : "",
        }
      end

      targets.uniq
    end

    private def haskell_source?(path : String) : Bool
      path.ends_with?(".hs") || path.ends_with?(".lhs")
    end

    private def extract_type_aliases(content : String) : Array(NamedTuple(name: String, body: String, line: Int32))
      results = [] of NamedTuple(name: String, body: String, line: Int32)
      cleaned = strip_haskell_comments(content)
      lines = cleaned.lines

      i = 0
      while i < lines.size
        line = lines[i]
        match = line.match(/^type\s+([A-Z][A-Za-z0-9_']*)(?:\s+[a-z][A-Za-z0-9_']*)*\s*=\s*(.*)$/)
        if match
          name = match[1]
          first_body = match[2]
          start_line = i + 1
          body_parts = [first_body]
          j = i + 1
          while j < lines.size
            next_line = lines[j]
            if next_line.lstrip.empty?
              # A blank line — which may be a stripped full-line comment sitting
              # between routes — does not necessarily terminate the alias. Peek
              # past the blank run: keep collecting only when a real
              # continuation line follows, otherwise the declaration has ended.
              k = j + 1
              while k < lines.size && lines[k].lstrip.empty?
                k += 1
              end
              break unless k < lines.size && continuation_line?(lines[k])
              j = k
            elsif continuation_line?(next_line)
              body_parts << next_line
              j += 1
            else
              break
            end
          end
          body = body_parts.join("\n").strip
          results << {name: name, body: body, line: start_line}
          i = j
        else
          i += 1
        end
      end

      results
    end

    # Extract `Servant.API.Generic` record-route declarations:
    #
    #   data RecordRoutes mode = RecordRoutes
    #     { version :: mode :- "version" :> Get '[JSON] Int
    #     , echo    :: mode :- "echo" :> Capture "s" String :> Get '[JSON] String
    #     }
    #
    # Each `field :: mode :- <route>` carries one route; the record is returned
    # as a pseudo type alias whose body is the routes joined with `:<|>`, so the
    # downstream alias machinery (reference counting, expansion, processing)
    # treats it exactly like a `type X = ...` API.
    private def extract_record_routes(content : String) : Array(NamedTuple(name: String, body: String, line: Int32))
      results = [] of NamedTuple(name: String, body: String, line: Int32)
      cleaned = strip_haskell_comments(content)
      lines = cleaned.lines

      i = 0
      while i < lines.size
        match = lines[i].match(/^(?:data|newtype)\s+([A-Z][A-Za-z0-9_']*)\s+[a-z][A-Za-z0-9_']*\b/)
        unless match
          i += 1
          next
        end

        name = match[1]
        start_line = i + 1

        # Collect from the declaration through the closing brace of the record.
        open_index = find_record_open_brace(lines, i)
        unless open_index
          i += 1
          next
        end

        block, next_index = collect_record_block(lines, open_index)
        routes = record_field_routes(block)
        if routes.size > 0
          results << {name: name, body: routes.join(" :<|> "), line: start_line}
        end
        i = next_index
      end

      results
    end

    # Locate the `{` that opens the record's field list, scanning at most a few
    # lines past the `data`/`newtype` head (the brace is often on the next line).
    private def find_record_open_brace(lines : Array(String), decl_index : Int32) : Int32?
      i = decl_index
      limit = Math.min(lines.size, decl_index + 4)
      while i < limit
        return i if lines[i].includes?('{')
        # Stop if another top-level declaration starts before any brace.
        return if i > decl_index && !lines[i].lstrip.empty? && !starts_with_whitespace?(lines[i]) && !lines[i].lstrip.starts_with?("=")
        i += 1
      end
      nil
    end

    # Return the text between the record's outermost `{` and matching `}` plus
    # the index of the line after the closing brace.
    private def collect_record_block(lines : Array(String), open_index : Int32) : Tuple(String, Int32)
      buffer = String::Builder.new
      depth = 0
      started = false
      i = open_index
      while i < lines.size
        line = lines[i]
        line.each_char do |char|
          if char == '{'
            depth += 1
            started = true
            next
          elsif char == '}'
            depth -= 1
            next if depth <= 0
          end
          buffer << char if started && depth >= 1
        end
        if started && depth <= 0
          return {buffer.to_s, i + 1}
        end
        buffer << '\n' if started
        i += 1
      end
      {buffer.to_s, i}
    end

    # Split a record body into its per-field route types, keeping only fields of
    # the form `name :: mode :- <route>` and returning the `<route>` part.
    private def record_field_routes(block : String) : Array(String)
      routes = [] of String
      split_top_level(block, ",").each do |field|
        idx = field.index(":-")
        next unless idx
        route = field[(idx + 2)..].strip
        routes << route unless route.empty?
      end
      routes
    end

    # Drop the `NamedRoutes` combinator keyword. After expansion a nested record
    # reference reads `... :> NamedRoutes (<expanded body>)`; removing the bare
    # word leaves `... :> (<expanded body>)`, a plain nested route.
    private def strip_named_routes(body : String) : String
      body.gsub(/\bNamedRoutes\b/, " ")
    end

    private def starts_with_whitespace?(line : String) : Bool
      first = line[0]?
      return false unless first
      first == ' ' || first == '\t'
    end

    private def continuation_line?(line : String) : Bool
      return true if starts_with_whitespace?(line)
      stripped = line.lstrip
      stripped.starts_with?(":<|>") || stripped.starts_with?(":>")
    end

    private def strip_haskell_comments(text : String) : String
      result = String::Builder.new
      chars = text.chars
      i = 0
      brace_depth = 0
      in_string = false

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size
            result << c
            result << chars[i + 1]
            i += 2
            next
          elsif c == '"'
            in_string = false
            result << c
            i += 1
            next
          else
            result << c
            i += 1
            next
          end
        end

        if brace_depth == 0 && c == '"'
          in_string = true
          result << c
          i += 1
          next
        end

        if i + 1 < chars.size && c == '{' && chars[i + 1] == '-'
          # Replace the comment with whitespace, PRESERVING newlines, so a
          # multi-line `{- -}` doesn't collapse lines and shift every later
          # endpoint's reported line number (mirrors scotty.cr).
          brace_depth += 1
          result << ' '
          result << ' '
          i += 2
          while i < chars.size && brace_depth > 0
            if i + 1 < chars.size && chars[i] == '-' && chars[i + 1] == '}'
              brace_depth -= 1
              result << ' '
              result << ' '
              i += 2
            elsif i + 1 < chars.size && chars[i] == '{' && chars[i + 1] == '-'
              brace_depth += 1
              result << ' '
              result << ' '
              i += 2
            else
              result << (chars[i] == '\n' ? '\n' : ' ')
              i += 1
            end
          end
          next
        end

        if brace_depth == 0 && i + 1 < chars.size && c == '-' && chars[i + 1] == '-'
          while i < chars.size && chars[i] != '\n'
            i += 1
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end

    private def referenced_aliases(body : String, known_names : Array(String)) : Array(String)
      found = Set(String).new
      body.scan(/\b([A-Z][A-Za-z0-9_']*)\b/) do |match|
        next if match.size < 2
        name = match[1]
        found << name if known_names.includes?(name)
      end
      found.to_a
    end

    private def alias_names_for_base(type_aliases : TypeAliasIndex, base_path : String) : Array(String)
      type_aliases.keys.compact_map { |key| key[1] if key[0] == base_path }
    end

    # `visited` only blocks cycles along one path, not repeated sibling
    # expansions (`type A = B :<|> B` doubles each level -> O(2^N)). Cap the
    # total expanded size so a crafted alias chain can't hang/OOM the scan;
    # real Servant bodies expand to far under this, so output is unchanged.
    MAX_EXPANSION_BYTES = 1_000_000

    private def expand_references(body : String, type_aliases : TypeAliasIndex, base_path : String) : String
      do_expand(body, type_aliases, base_path, Set(String).new, [MAX_EXPANSION_BYTES])
    end

    private def do_expand(body : String, type_aliases : TypeAliasIndex, base_path : String, visited : Set(String), budget : Array(Int32)) : String
      body.gsub(/\b([A-Z][A-Za-z0-9_']*)\b/) do |raw, m|
        name = m[1]
        key = {base_path, name}
        if budget[0] <= 0
          raw # budget exhausted: leave the reference unexpanded
        elsif type_aliases.has_key?(key) && !visited.includes?(name)
          new_visited = visited.dup
          new_visited << name
          sub = type_aliases[key][:body]
          budget[0] -= sub.bytesize
          "(#{do_expand(sub, type_aliases, base_path, new_visited, budget)})"
        else
          raw
        end
      end
    end

    private def contains_servant_signature?(body : String) : Bool
      return true if body.includes?(":<|>")
      return true if body.includes?(":>") && body.match(/\b(Get|Post|Put|Delete|Patch|Options|Head|Verb)\b/)
      false
    end

    private def process_api_body(source : String, line_number : Int32, body : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      flat = flatten_alternatives(body)
      routes = split_top_level(flat, ":<|>")
      routes.each do |route|
        if endpoint = process_route(source, line_number, route)
          endpoints << endpoint
        end
      end
      endpoints
    end

    private def attach_servant_callees(api_name : String,
                                       api_source : String,
                                       endpoints : Array(Endpoint),
                                       handler_bodies : HandlerBodies,
                                       server_bindings : ServerBindings)
      leaf_names = server_leaf_names_for(api_name, api_source, endpoints.size, handler_bodies, server_bindings)
      return unless leaf_names

      base_path = configured_base_for(api_source)
      endpoints.zip(leaf_names).each do |endpoint, handler_name|
        handler_body = unique_handler_body(handler_name, base_path, handler_bodies)
        next unless handler_body

        callees = Noir::HaskellCalleeExtractor.callees_for_body(
          handler_body[:body],
          handler_body[:path],
          handler_body[:start_line]
        )
        Noir::HaskellCalleeExtractor.attach_to(endpoint, callees)
      end
    end

    private def server_leaf_names_for(api_name : String,
                                      api_source : String,
                                      endpoint_count : Int32,
                                      handler_bodies : HandlerBodies,
                                      server_bindings : ServerBindings) : Array(String)?
      server_candidate_names(api_name, api_source, server_bindings).each do |server_name|
        binding = body_for_path(server_name, api_source, handler_bodies)
        next unless binding
        next unless root_server_matches_api?(server_name, api_source, api_name, server_bindings)

        visited = Set(Tuple(String, String)).new
        visited << {binding[:path], server_name}
        leaves = flatten_server_expression(binding[:body], handler_bodies, server_bindings, binding[:path], visited)
        next unless leaves
        next unless leaves.size == endpoint_count
        # The server is already confirmed by its `:: Server <api>` binding and an
        # exact leaf/endpoint count match, so require only that at least one leaf
        # names a known function (proving the flatten landed on real handlers).
        # Handlers that are imported, point-free, or collide across modules then
        # simply contribute no callees rather than sinking the whole server —
        # `attach_servant_callees` resolves each leaf independently.
        base_path = configured_base_for(api_source)
        next unless leaves.any? { |leaf| handler_bodies.has_key?(handler_key(base_path, leaf)) }

        return leaves
      end

      nil
    end

    private def server_candidate_names(api_name : String,
                                       api_source : String,
                                       server_bindings : ServerBindings) : Array(String)
      candidates = ["server", "#{lower_camel(api_name)}Server"]

      if api_name.ends_with?("API")
        prefix = api_name[0...(api_name.size - "API".size)]
        candidates << "#{lower_camel(prefix)}Server" unless prefix.empty?
      end

      # Servers are frequently named arbitrarily (`exchangeServer`, `appToServer`)
      # rather than following the `<api>Server` convention. Any binding in the
      # same file whose `:: Server <api>` / `:: ServerT <api>` signature targets
      # this API is a valid server root regardless of its name.
      server_bindings.each do |key, target|
        candidates << key[1] if key[0] == api_source && target == api_name
      end

      candidates.uniq
    end

    private def lower_camel(name : String) : String
      return name if name.empty?

      name[0].downcase.to_s + name[1..]
    end

    private def flatten_server_expression(expression : String,
                                          handler_bodies : HandlerBodies,
                                          server_bindings : ServerBindings,
                                          current_path : String,
                                          visited : Set(Tuple(String, String))) : Array(String)?
      parts = split_top_level(expression, ":<|>")
      leaves = [] of String

      parts.each do |part|
        part_leaves = flatten_server_part(part, handler_bodies, server_bindings, current_path, visited)
        return unless part_leaves

        leaves.concat(part_leaves)
      end

      leaves
    end

    private def flatten_server_part(part : String,
                                    handler_bodies : HandlerBodies,
                                    server_bindings : ServerBindings,
                                    current_path : String,
                                    visited : Set(Tuple(String, String))) : Array(String)?
      name = leaf_value_name(unwrap_parens(part.strip))
      return unless name

      binding = body_for_path(name, current_path, handler_bodies)
      if binding
        key = {current_path, name}
        server_binding = server_bindings.has_key?(key) || server_like_name?(name)
        if (server_binding || binding[:body].includes?(":<|>")) && !visited.includes?(key)
          visited << key
          expanded = flatten_server_expression(binding[:body], handler_bodies, server_bindings, binding[:path], visited)
          visited.delete(key)
          return expanded if expanded && expanded.size > 0
          return if server_binding
        end
      end

      return if server_like_name?(name) || server_binding_name?(name, server_bindings)

      [name]
    end

    # Resolve a single server expression down to the value name that identifies
    # its handler. A bare name is returned as-is; an application keeps its head
    # function (`Handler.rates s` -> `rates`, `mkHandler cfg` -> `mkHandler`).
    # `hoistServer`/`enter` wrap the real server in their last argument, and
    # `return x`/`pure x` produce a constant response from `x`.
    private def leaf_value_name(expr : String) : String?
      return expr if simple_value_name?(expr)

      tokens = expr.split(/\s+/).reject(&.empty?)
      return if tokens.empty?

      head = qualified_tail(tokens[0])
      if {"hoistServer", "hoistServerWithContext", "enter"}.includes?(head) && tokens.size >= 2
        head = qualified_tail(tokens[-1])
      elsif {"return", "pure"}.includes?(head) && tokens.size >= 2
        head = qualified_tail(tokens[1])
      end

      simple_value_name?(head) ? head : nil
    end

    # Strip a module qualifier and stray parentheses: `Mod.Sub.fn` -> `fn`,
    # `(handler` -> `handler`.
    private def qualified_tail(token : String) : String
      token.strip.gsub(/[()]/, "").split('.').last
    end

    private def root_server_matches_api?(server_name : String,
                                         api_source : String,
                                         api_name : String,
                                         server_bindings : ServerBindings) : Bool
      server_bindings[{api_source, server_name}]? == api_name
    end

    private def body_for_path(name : String, path : String, handler_bodies : HandlerBodies) : HandlerBody?
      bodies = handler_bodies[handler_key(configured_base_for(path), name)]?
      return unless bodies

      bodies.find { |body| body[:path] == path }
    end

    private def unique_handler_body(name : String, base_path : String, handler_bodies : HandlerBodies) : HandlerBody?
      bodies = handler_bodies[handler_key(base_path, name)]?
      return unless bodies && bodies.size == 1

      bodies.first
    end

    private def server_like_name?(name : String) : Bool
      name == "server" || name.ends_with?("Server")
    end

    private def server_binding_name?(name : String, server_bindings : ServerBindings) : Bool
      server_bindings.keys.any? { |key| key[1] == name }
    end

    private def simple_value_name?(name : String) : Bool
      !!name.match(/\A[a-z_][A-Za-z0-9_']*\z/)
    end

    private def flatten_alternatives(body : String) : String
      current = body
      loop do
        routes = split_top_level(current, ":<|>")
        expanded = [] of String
        changed = false

        routes.each do |route|
          distributed = distribute_route(route)
          changed = true if distributed.size > 1
          expanded.concat(distributed)
        end

        next_body = expanded.join(" :<|> ")
        break next_body unless changed
        current = next_body
      end
    end

    private def distribute_route(route : String) : Array(String)
      segments = split_top_level(route, ":>")

      segments.each_with_index do |segment, idx|
        inner = unwrap_parens(segment.strip)
        next if inner == segment.strip
        sub_routes = split_top_level(inner, ":<|>")
        next if sub_routes.size <= 1

        results = [] of String
        sub_routes.each do |sub|
          new_segments = segments.dup
          new_segments[idx] = sub
          results << new_segments.join(" :> ")
        end
        return results
      end

      [route]
    end

    # Split a route into its `:>` segments, recursing into parenthesised
    # sub-chains. `:>` is right-associative, so `A :> (B :> C)` is the same route
    # as `A :> B :> C`; a nested `NamedRoutes` record expands to a parenthesised
    # `:>` chain that must be spliced in rather than treated as one opaque
    # segment.
    private def flatten_route_segments(raw : String) : Array(String)
      result = [] of String
      split_top_level(raw, ":>").each do |segment|
        seg = unwrap_parens(segment.strip)
        next if seg.empty?

        if split_top_level(seg, ":>").size > 1
          result.concat(flatten_route_segments(seg))
        else
          result << seg
        end
      end
      result
    end

    private def process_route(source : String, line_number : Int32, route : String) : Endpoint?
      raw = unwrap_parens(route.strip)
      return if raw.empty?

      segments = flatten_route_segments(raw)

      url_parts = [] of String
      params = [] of Param
      method = nil.as(String?)

      segments.each do |segment|
        seg = unwrap_parens(segment.strip)
        next if seg.empty?

        lit = match_string_literal(seg)
        if lit
          url_parts << lit
          next
        end

        head, args = split_head_args(seg)

        case head
        when "Capture", "Capture'"
          name = extract_string_arg(args)
          type = extract_type_arg(args)
          if name
            url_parts << ":#{name}"
            params << Param.new(name, type, "path")
          end
        when "CaptureAll"
          name = extract_string_arg(args)
          type = extract_type_arg(args)
          if name
            url_parts << "*#{name}"
            params << Param.new(name, type, "path")
          end
        when "QueryParam", "QueryParam'", "QueryParams"
          name = extract_string_arg(args)
          type = extract_type_arg(args)
          params << Param.new(name, type, "query") if name
        when "QueryFlag"
          name = extract_string_arg(args)
          params << Param.new(name, "Bool", "query") if name
        when "Header", "Header'"
          name = extract_string_arg(args)
          type = extract_type_arg(args)
          params << Param.new(name, type, "header") if name
        when "ReqBody", "ReqBody'", "StreamBody", "StreamBody'"
          type = extract_type_arg(args)
          params << Param.new("body", type, "body")
        when "MultipartForm", "MultipartForm'"
          # `MultipartForm Mem (MultipartData Mem)` — second positional
          # argument carries the data type; fall back to "Multipart" when
          # not parseable.
          type = extract_multipart_type(args)
          params << Param.new("body", type, "body")
        else
          mapped = http_method_for(head)
          if mapped
            method = mapped
          elsif head == "Verb" || head == "UVerb"
            verb = extract_verb_method(args)
            method = verb if verb
          elsif head == "Stream"
            # `Stream 'GET 200 NewlineFraming JSON ...` — first positional
            # token is the HTTP verb (optionally promoted with a leading `'`).
            verb = extract_verb_method(args)
            method = verb if verb
          end
        end
      end

      resolved_method = method
      return unless resolved_method

      url = url_parts.empty? ? "/" : "/#{url_parts.join("/")}"
      details = Details.new(PathInfo.new(source, line_number))
      endpoint_params = params.map { |p| Param.new(p.name, p.value, p.param_type) }
      Endpoint.new(url, resolved_method, endpoint_params, details)
    end

    private def http_method_for(token : String) : String?
      case token
      when "Get", "GetNoContent", "StreamGet"
        "GET"
      when "Post", "PostNoContent", "PostCreated", "PostAccepted",
           "PostNonAuthoritative", "PostResetContent", "StreamPost"
        "POST"
      when "Put", "PutNoContent", "PutCreated", "PutAccepted", "StreamPut"
        "PUT"
      when "Delete", "DeleteNoContent", "DeleteAccepted", "StreamDelete"
        "DELETE"
      when "Patch", "PatchNoContent", "StreamPatch"
        "PATCH"
      when "Head"
        "HEAD"
      when "Options"
        "OPTIONS"
      end
    end

    private def extract_multipart_type(args : String) : String
      remaining = args.strip
      # Skip the first positional argument (typically `Mem` or `Tmp`).
      m = remaining.match(/\A[A-Za-z][A-Za-z0-9_']*\s*(.*)\z/m)
      remaining = m[1] if m
      remaining = remaining.strip
      # The next token is either `(MultipartData Mem)` or a bare type
      # constructor. Strip a leading paren if present.
      remaining = remaining[1..].strip if remaining.starts_with?("(")
      m = remaining.match(/\A([A-Za-z][A-Za-z0-9_']*)/)
      m ? m[1] : "Multipart"
    end

    private def extract_verb_method(args : String) : String?
      m = args.match(/'?\s*([A-Z]+)/)
      return unless m
      verb = m[1]
      verb if HTTP_METHOD_VERBS.includes?(verb)
    end

    private def match_string_literal(segment : String) : String?
      m = segment.match(/\A"((?:[^"\\]|\\.)*)"\z/)
      m ? m[1] : nil
    end

    private def split_head_args(segment : String) : Tuple(String, String)
      idx = 0
      while idx < segment.size && !segment[idx].whitespace?
        idx += 1
      end
      head = segment[0...idx]
      args = idx < segment.size ? segment[idx..].strip : ""
      {head, args}
    end

    private def extract_string_arg(args : String) : String?
      m = args.match(/"((?:[^"\\]|\\.)*)"/)
      m ? m[1] : nil
    end

    private def extract_type_arg(args : String) : String
      remaining = args
      m = args.match(/"(?:[^"\\]|\\.)*"\s*(.*)$/m)
      remaining = m[1] if m
      remaining = remaining.strip
      remaining = skip_promoted_lists(remaining)
      m = remaining.match(/\A([A-Za-z][A-Za-z0-9_']*)/)
      m ? m[1] : ""
    end

    private def skip_promoted_lists(input : String) : String
      remaining = input
      while remaining.starts_with?("'[")
        depth = 0
        idx = 0
        chars = remaining.chars
        while idx < chars.size
          c = chars[idx]
          if c == '['
            depth += 1
          elsif c == ']'
            depth -= 1
            if depth == 0
              idx += 1
              break
            end
          end
          idx += 1
        end
        remaining = idx < remaining.size ? remaining[idx..].strip : ""
      end
      remaining
    end

    private def unwrap_parens(text : String) : String
      stripped = text.strip
      while stripped.starts_with?("(") && stripped.ends_with?(")") && balanced_outermost?(stripped)
        stripped = stripped[1...-1].strip
      end
      stripped
    end

    private def balanced_outermost?(text : String) : Bool
      return false unless text.starts_with?("(") && text.ends_with?(")")
      depth = 0
      text.each_char_with_index do |c, i|
        if c == '('
          depth += 1
        elsif c == ')'
          depth -= 1
          return false if depth == 0 && i < text.size - 1
        end
      end
      depth == 0
    end

    private def split_top_level(input : String, separator : String) : Array(String)
      parts = [] of String
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
      start = 0
      i = 0
      sep_size = separator.size

      while i < input.size
        c = input[i]
        if c == '"'
          i += 1
          while i < input.size && input[i] != '"'
            i += 1 if input[i] == '\\' && i + 1 < input.size
            i += 1
          end
          i += 1 if i < input.size
          next
        end

        if c == '('
          paren_depth += 1
        elsif c == ')'
          paren_depth -= 1 if paren_depth > 0
        elsif c == '['
          bracket_depth += 1
        elsif c == ']'
          bracket_depth -= 1 if bracket_depth > 0
        elsif c == '{'
          brace_depth += 1
        elsif c == '}'
          brace_depth -= 1 if brace_depth > 0
        elsif paren_depth == 0 && bracket_depth == 0 && brace_depth == 0 && matches_at?(input, i, separator)
          parts << input[start...i]
          i += sep_size
          start = i
          next
        end

        i += 1
      end

      parts << input[start..]
      parts.map(&.strip).reject(&.empty?)
    end

    private def matches_at?(input : String, index : Int32, sep : String) : Bool
      return false if index + sep.size > input.size
      sep.size.times do |k|
        return false if input[index + k] != sep[k]
      end
      true
    end
  end
end
