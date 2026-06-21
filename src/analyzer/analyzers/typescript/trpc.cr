require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Typescript
  class TRPC < Analyzer::Javascript::JavascriptEngine
    DEFAULT_PREFIX = "/api/trpc"
    alias RouterKey = Tuple(String, String)

    private struct Router
      getter base_path : String
      getter name : String
      getter body : String
      getter file : String
      getter line : Int32

      def initialize(@base_path : String, @name : String, @body : String, @file : String, @line : Int32)
      end
    end

    # A procedure exported as a standalone `const` and referenced by name
    # inside a router map — the modular layout large tRPC apps use
    # (documenso: `export const createDocumentRoute = authenticatedProcedure
    # .input(...).mutation(...)` per file, then `router({ createDocument:
    # createDocumentRoute })`). `value` is the chain up to (and including)
    # the terminal `.query/.mutation/.subscription(` so input params and
    # callees resolve.
    private struct Procedure
      getter base_path : String
      getter name : String
      getter method : String
      getter value : String
      getter file : String
      getter line : Int32

      def initialize(@base_path, @name, @method, @value, @file, @line)
      end
    end

    def analyze
      result = [] of Endpoint
      routers = Hash(RouterKey, Router).new
      procedures = Hash(RouterKey, Procedure).new
      procedures_by_name = Hash(String, Procedure).new
      routers_mu = Mutex.new
      prefix_mu = Mutex.new
      url_prefixes = Hash(String, String).new

      parallel_file_scan([".js", ".ts", ".jsx", ".tsx", ".cts", ".mts", ".cjs", ".mjs"]) do |path|
        begin
          next if trpc_test_fixture_path?(path)

          raw = read_file_content(path)
          next unless trpc_candidate?(raw)
          # tRPC router modules may import `react` (RSC/client helpers); the
          # `createTRPCRouter`/procedure shape already gates detection, so
          # don't let the client-side-framework markers skip them.
          next if Noir::JSRouteExtractor.test_stub_only?(path, raw, include_client_frameworks: false)

          content = Noir::JSRouteExtractor.strip_js_comments(raw)
          next unless trpc_candidate?(content)

          literal_mask = string_literal_mask(content)
          base_path = configured_base_for(path)
          collected = collect_routers(content, path, base_path, literal_mask)
          collected_procs = collect_procedures(content, path, base_path, literal_mask)
          unless collected.empty? && collected_procs.empty?
            routers_mu.synchronize do
              collected.each { |r| routers[router_key(r)] = r }
              collected_procs.each do |p|
                procedures[router_key(p.base_path, p.name)] = p
                procedures_by_name[p.name] = p
              end
            end
          end
          if found = extract_prefix(content, literal_mask)
            prefix_mu.synchronize do
              url_prefixes[base_path] = found
            end
          end
        rescue e
          logger.debug "Error analyzing tRPC file #{path}: #{e.message}"
        end
        nil
      end

      return result if routers.empty?

      used_as_child = Set(RouterKey).new
      routers.each_value do |router|
        each_top_level_kv(router.body) do |_key, value, _value_line|
          ident = extract_identifier(value)
          next unless ident
          child_key = router_key(router.base_path, ident)
          used_as_child.add(child_key) if routers.has_key?(child_key)
        end
      end

      roots = routers.values.reject { |r| used_as_child.includes?(router_key(r)) }
      roots = routers.values if roots.empty?

      roots.each do |root|
        url_prefix = url_prefixes[root.base_path]? || DEFAULT_PREFIX
        flatten_router(root, "", routers, procedures, procedures_by_name, url_prefix, result, Set(RouterKey).new)
      end

      result
    end

    PROCEDURE_HINTS = [
      ".query(",
      ".query (",
      ".mutation(",
      ".mutation (",
      ".subscription(",
      ".subscription (",
    ]

    PREFIX_HINTS = [
      "endpoint:",
      "createExpressMiddleware",
      "createKoaMiddleware",
      "fastifyTRPCPlugin",
      "fastifyTRPC",
    ]

    V9_MERGE_HINTS = [
      ".merge(",
      ".merge (",
    ]

    private def trpc_candidate?(content : String) : Bool
      content.matches?(/endpoint\s*:/) ||
        PREFIX_HINTS.any? { |hint| content.includes?(hint) } ||
        content.includes?("initTRPC") ||
        content.includes?("createTRPCRouter") ||
        # A pure ROOT/sub-router composition file (`export const appRouter =
        # router({ document: documentRouter, ... })`) has no inline
        # procedure hint, so the old `router( && .query(` gate skipped it —
        # and with the root uncollected every sub-router was flattened
        # standalone, losing its dotted prefix. `router(` imported from a
        # *trpc* module disambiguates it from express/react-router.
        (content.includes?("router(") && trpc_router_import?(content)) ||
        # tRPC v9 used chain-style routers:
        # `createRouter().query("name", { input, resolve }).merge("x.", child)`.
        # OSS apps still use this shape, and it has no `Procedure` builder.
        v9_router_candidate?(content) ||
        # A standalone procedure-definition file (no `router(...)`).
        (procedure_builder?(content) && PROCEDURE_HINTS.any? { |hint| content.includes?(hint) })
    end

    private def v9_router_candidate?(content : String) : Bool
      return false unless content.includes?("createRouter") || content.includes?("trpc.router")

      V9_MERGE_HINTS.any? { |hint| content.includes?(hint) } ||
        PROCEDURE_HINTS.any? { |hint| content.includes?(hint) }
    end

    # tRPC builders are conventionally named `*Procedure` (publicProcedure,
    # protectedProcedure, authenticatedProcedure) or accessed as
    # `t.procedure`.
    private def procedure_builder?(content : String) : Bool
      content.includes?("Procedure") || content.includes?(".procedure")
    end

    # `import { router } from '.../trpc'` — tRPC's `router` factory, as
    # opposed to express's `Router()` or react-router's `router`.
    private def trpc_router_import?(content : String) : Bool
      content.matches?(/import\b[^;]*\brouter\b[^;]*from\s*['"][^'"]*trpc[^'"]*['"]/)
    end

    TEST_FIXTURE_PATH_MARKERS = [
      "/test/",
      "/tests/",
      "/__tests__/",
      "/e2e/",
      "/snapshots/",
      "/test-files/",
    ]

    private def trpc_test_fixture_path?(path : String) : Bool
      TEST_FIXTURE_PATH_MARKERS.any? { |marker| path.includes?(marker) } ||
        path.includes?(".test.") ||
        path.includes?(".spec.")
    end

    private def string_literal_mask(content : String) : Array(Bool)
      mask = Array(Bool).new(content.bytesize, false)
      i = 0

      while i < content.bytesize
        byte = content.byte_at(i)
        if byte == '\''.ord || byte == '"'.ord || byte == '`'.ord
          quote = byte
          mask[i] = true
          i += 1

          while i < content.bytesize
            current = content.byte_at(i)
            mask[i] = true

            if current == '\\'.ord && i + 1 < content.bytesize
              i += 1
              mask[i] = true
            elsif current == quote
              i += 1
              break
            end

            i += 1
          end
        else
          i += 1
        end
      end

      mask
    end

    private def literal_position?(literal_mask : Array(Bool), pos : Int32?) : Bool
      return false unless pos
      pos < literal_mask.size && literal_mask[pos]
    end

    private def router_key(router : Router) : RouterKey
      router_key(router.base_path, router.name)
    end

    private def router_key(base_path : String, name : String) : RouterKey
      {base_path, name}
    end

    private def collect_routers(content : String, path : String, base_path : String, literal_mask : Array(Bool)) : Array(Router)
      collected = [] of Router
      # Capture `(export )? (const|let|var) NAME = <prefix>?(router|createTRPCRouter)({...})`.
      # Prefix tolerates `t.router(`, `initTRPC.create().router(`, `_.router(` etc.
      pattern = /\b(?:export\s+)?(?:const|let|var)\s+(\w+)(?:\s*:[^=]+)?\s*=\s*(?:[\w$]+\s*(?:\(\s*\))?\s*\.\s*)?(?:router|createTRPCRouter)\s*\(\s*\{/

      content.scan(pattern) do |match|
        match_start = match.begin(0) || 0
        next if literal_position?(literal_mask, match_start)

        match_end = match.end(0) || 0
        next if match_end == 0

        brace_open = match_end - 1
        next unless content[brace_open]? == '{'

        brace_close = Noir::JSRouteExtractor.find_matching_brace(content, brace_open)
        next unless brace_close

        body = content[(brace_open + 1)...brace_close]
        line = content[0, match_start].count('\n') + 1
        collected << Router.new(base_path, match[1], body, path, line)
      end

      identifier_arg_pattern = /\b(?:export\s+)?(?:const|let|var)\s+(\w+)(?:\s*:[^=]+)?\s*=\s*(?:[\w$]+\s*(?:\(\s*\))?\s*\.\s*)?(?:router|createTRPCRouter)\s*\(\s*([A-Za-z_$][\w$]*)\s*\)/

      content.scan(identifier_arg_pattern) do |match|
        match_start = match.begin(0) || 0
        next if literal_position?(literal_mask, match_start)

        body_info = extract_object_assignment_body(content, match[2], literal_mask)
        next unless body_info

        body, object_line = body_info
        line = object_line > 0 ? object_line : content[0, match_start].count('\n') + 1
        collected << Router.new(base_path, match[1], body, path, line)
      end

      collected.concat collect_v9_chain_routers(content, path, base_path, literal_mask)

      collected
    end

    private def collect_v9_chain_routers(content : String, path : String, base_path : String, literal_mask : Array(Bool)) : Array(Router)
      collected = [] of Router
      assignment_pattern = /\b(?:export\s+)?(?:const|let|var)\s+(\w+)(?:\s*:[^=]+)?\s*=\s*/

      content.scan(assignment_pattern) do |match|
        match_start = match.begin(0) || 0
        next if literal_position?(literal_mask, match_start)

        value_start = skip_whitespace(content, match.end(0) || 0)
        statement_end = find_statement_end(content, value_start)
        expression = content[value_start...statement_end]
        next unless v9_router_chain_expression?(expression)

        line = content[0, match_start].count('\n') + 1
        body = v9_router_chain_body(expression, content, value_start, line)
        next if body.empty?

        collected << Router.new(base_path, match[1], body, path, line)
      end

      collected
    end

    private def v9_router_chain_expression?(expression : String) : Bool
      return false unless expression.includes?("createRouter") || expression.includes?("trpc.router")

      expression.includes?(".merge") ||
        expression.includes?(".query") ||
        expression.includes?(".mutation") ||
        expression.includes?(".subscription")
    end

    private def find_statement_end(content : String, start : Int32) : Int32
      depth = 0
      quote : Char? = nil
      escaped = false
      i = start

      while i < content.size
        char = content[i]

        if quote
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
          i += 1
          next
        end

        case char
        when '\'', '"', '`'
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when '\n'
          if depth == 0
            next_pos = i + 1
            while next_pos < content.size && (content[next_pos] == ' ' || content[next_pos] == '\t')
              next_pos += 1
            end
            return i unless content[next_pos]? == '.'
          end
        when ';'
          return i if depth == 0
        end

        i += 1
      end

      content.size
    end

    private def skip_whitespace(content : String, pos : Int32) : Int32
      i = pos
      while i < content.size && content[i].whitespace?
        i += 1
      end
      i
    end

    private def v9_router_chain_body(expression : String, content : String, expression_start : Int32, assignment_line : Int32) : String
      entries = [] of Tuple(Int32, Int32, String, String)

      # Precompute newline offsets once so per-entry line lookups stay O(log n)
      # instead of re-slicing `content[0, ...].count('\n')` for every chained
      # `.query`/`.merge` (which is O(n²) on long single-expression chains).
      base_newlines = expression_start == 0 ? 0 : content[0, expression_start].count('\n')
      expr_newlines = [] of Int32
      expression.each_char_with_index { |char, index| expr_newlines << index if char == '\n' }

      expression.scan(/\.\s*(query|mutation|subscription)\s*\(\s*(['"`])([^'"`]+)\2\s*,/m) do |match|
        match_start = match.begin(0) || 0
        open_paren = expression.index('(', match_start)
        next unless open_paren

        close_paren = Noir::JSRouteExtractor.find_matching_paren(expression, open_paren)
        next unless close_paren

        line = base_newlines + newline_count_before(expr_newlines, match_start) + 1
        entries << {line, match_start, match[3], expression[match_start..close_paren]}
      end

      expression.scan(/\.\s*merge\s*\(/m) do |match|
        match_start = match.begin(0) || 0
        open_paren = expression.index('(', match_start)
        next unless open_paren

        close_paren = Noir::JSRouteExtractor.find_matching_paren(expression, open_paren)
        next unless close_paren

        args = split_top_level(expression[(open_paren + 1)...close_paren], ',')
        next if args.empty?

        prefix : String?
        child : String?
        if args.size >= 2
          prefix = string_literal_value(args[0])
          child = extract_identifier(args[1])
        else
          prefix = nil
          child = extract_identifier(args[0])
        end
        next unless child

        key = normalize_v9_merge_prefix(prefix, child)
        next if key.empty?

        line = base_newlines + newline_count_before(expr_newlines, match_start) + 1
        entries << {line, match_start, key, child}
      end

      return "" if entries.empty?

      builder = String::Builder.new
      current_line = 1
      entries.sort_by { |line, pos, _key, _value| {line, pos} }.each do |line, _pos, key, value|
        target_line = line - assignment_line + 1
        current_line = append_router_body_entry(builder, current_line, target_line, key, value)
      end

      builder.to_s
    end

    # Count newlines occurring strictly before `pos` using the precomputed,
    # ascending list of newline offsets (binary search keeps it O(log n)).
    private def newline_count_before(newline_positions : Array(Int32), pos : Int32) : Int32
      newline_positions.bsearch_index { |offset| offset >= pos } || newline_positions.size
    end

    private def append_router_body_entry(builder : String::Builder, current_line : Int32, target_line : Int32, key : String, value : String) : Int32
      line = current_line
      while line < target_line
        builder << '\n'
        line += 1
      end

      builder << quoted_router_key(key)
      builder << ": "
      builder << value
      builder << ",\n"
      line + value.count('\n') + 1
    end

    private def quoted_router_key(key : String) : String
      escaped = key.gsub("\\", "\\\\").gsub("\"", "\\\"")
      "\"#{escaped}\""
    end

    private def string_literal_value(expression : String) : String?
      stripped = expression.strip
      if match = stripped.match(/\A(['"`])([^'"`]*)\1\z/)
        match[2]
      end
    end

    private def normalize_v9_merge_prefix(prefix : String?, child : String) : String
      raw = prefix || child
      raw.strip.gsub(/\A\.+|\.+\z/, "")
    end

    PROCEDURE_VERBS = {"query" => "GET", "mutation" => "POST", "subscription" => "SUBSCRIBE"}

    # Collect standalone `export const NAME = <builder>.input(...).<verb>(...)`
    # procedure definitions so a router that references NAME resolves it.
    private def collect_procedures(content : String, path : String, base_path : String, literal_mask : Array(Bool)) : Array(Procedure)
      collected = [] of Procedure
      content.scan(/\b(?:export\s+)?(?:const|let|var)\s+(\w+)(?:\s*:[^=]+)?\s*=\s*/) do |match|
        match_start = match.begin(0) || 0
        next if literal_position?(literal_mask, match_start)

        value_start = match.end(0) || 0
        first = content[value_start]?
        next unless first && (first.ascii_letter? || first == '_' || first == '$')

        info = procedure_terminal(content, value_start)
        next unless info
        method, value = info
        line = content[0, match_start].count('\n') + 1
        collected << Procedure.new(base_path, match[1], method, value, path, line)
      end
      collected
    end

    # Walk the call chain from `start` (a procedure-builder identifier) and
    # return {http_method, chain_text} once a TOP-LEVEL
    # `.query/.mutation/.subscription(` terminal is found. Nested parens —
    # the `.input(z.object({...}))` schema, refinement arrows, the resolver
    # — sit at depth > 0, so only the procedure's own terminal verb matches.
    private def procedure_terminal(content : String, start : Int32) : Tuple(String, String)?
      i = start
      depth = 0
      limit = Math.min(content.size, start + 8000)
      while i < limit
        case content[i]
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1
          return if depth < 0
        when ';'
          return if depth == 0
        when '.'
          if depth == 0
            PROCEDURE_VERBS.each do |verb, method|
              return {method, content[start...i]} if verb_call_at?(content, i + 1, verb)
            end
          end
        else
          # not interesting
        end
        i += 1
      end
      nil
    end

    private def verb_call_at?(content : String, pos : Int32, verb : String) : Bool
      return false if pos + verb.size > content.size
      verb.each_char_with_index do |ch, k|
        return false unless content[pos + k] == ch
      end
      after = pos + verb.size
      if nxt = content[after]?
        return false if nxt.ascii_alphanumeric? || nxt == '_'
      end
      j = after
      while j < content.size && content[j].whitespace?
        j += 1
      end
      content[j]? == '('
    end

    private def extract_object_assignment_body(content : String, identifier : String, literal_mask : Array(Bool)) : Tuple(String, Int32)?
      pattern = cached_regex("trpc:object_assign:#{identifier}") do
        /\b(?:export\s+)?(?:const|let|var)\s+#{Regex.escape(identifier)}(?:\s*:[^=]+)?\s*=\s*\{/
      end

      content.scan(pattern) do |match|
        match_start = match.begin(0) || 0
        next if literal_position?(literal_mask, match_start)

        match_end = match.end(0) || 0
        next if match_end == 0

        brace_open = match_end - 1
        next unless content[brace_open]? == '{'

        brace_close = Noir::JSRouteExtractor.find_matching_brace(content, brace_open)
        next unless brace_close

        body = content[(brace_open + 1)...brace_close]
        line = content[0, match_start].count('\n') + 1
        return {body, line}
      end

      nil
    end

    private def extract_prefix(content : String, literal_mask : Array(Bool)) : String?
      # Explicit endpoint option in fetch/openapi handlers.
      content.scan(/endpoint\s*:\s*['"`]([^'"`]+)['"`]/) do |m|
        next if literal_position?(literal_mask, m.begin(0))
        # Skip TS *type* annotations like `endpoint: `/${string}`` — a
        # template literal carrying an interpolation is a type/computed
        # value, not the concrete mount path (documenso's
        # openapi-fetch-handler types `endpoint` this way; the real prefix
        # `'/api/trpc'` lives in another file).
        next if m[1].includes?("${")
        return m[1]
      end

      # Express/Koa-style mounting: `app.use('/api/trpc', trpcExpress.createExpressMiddleware(...))`.
      content.scan(/\.\s*use\s*\(\s*['"`]([^'"`]+)['"`]\s*,\s*[^)]*?(?:trpcExpress\.createExpressMiddleware|createExpressMiddleware|createKoaMiddleware)/m) do |m|
        next if literal_position?(literal_mask, m.begin(0))
        return m[1]
      end

      # Fastify plugin: `fastify.register(fastifyTRPCPlugin, { prefix: '/api/trpc' })`.
      content.scan(/(?:fastifyTRPCPlugin|fastifyTRPC)\b[^)]*?prefix\s*:\s*['"`]([^'"`]+)['"`]/m) do |m|
        next if literal_position?(literal_mask, m.begin(0))
        return m[1]
      end

      nil
    end

    private def each_top_level_kv(body : String, &)
      i = 0
      n = body.size
      while i < n
        while i < n && (body[i].whitespace? || body[i] == ',' || body[i] == ';')
          i += 1
        end
        break if i >= n

        key = case body[i]
              when '\'', '"', '`'
                quote = body[i]
                j = i + 1
                while j < n && body[j] != quote
                  j += body[j] == '\\' ? 2 : 1
                end
                literal = body[(i + 1)...j]
                i = j < n ? j + 1 : j
                literal
              when '['
                # Computed key like ['foo']: ... — skip the bracket span.
                if close = find_matching_bracket(body, i)
                  literal = body[(i + 1)...close].strip.gsub(/^['"`]|['"`]$/, "")
                  i = close + 1
                  literal
                else
                  i = skip_top_level_to_comma(body, i)
                  ""
                end
              else
                c = body[i]
                if c.ascii_letter? || c == '_' || c == '$'
                  j = i
                  while j < n && (body[j].ascii_alphanumeric? || body[j] == '_' || body[j] == '$')
                    j += 1
                  end
                  literal = body[i...j]
                  i = j
                  literal
                else
                  i = skip_top_level_to_comma(body, i)
                  ""
                end
              end

        if key.empty?
          next
        end

        while i < n && body[i].whitespace?
          i += 1
        end

        if i >= n || body[i] == ','
          # Shorthand: `userRouter,` — value is the same identifier.
          value_line = body[0, i].count('\n') + 1
          yield key, key, value_line unless key.empty?
          i += 1 if i < n && body[i] == ','
          next
        end

        unless body[i] == ':'
          # Spread, method shorthand, or other construct we don't handle.
          i = skip_top_level_to_comma(body, i)
          next
        end

        i += 1
        value_start = i
        value_end = skip_top_level_to_comma(body, i)
        value = body[value_start...value_end]
        value_line = body[0, value_start].count('\n') + 1
        yield key, value, value_line unless key.empty?
        i = value_end
      end
    end

    private def find_matching_bracket(body : String, open : Int32) : Int32?
      depth = 0
      i = open
      n = body.size
      while i < n
        c = body[i]
        if c == '['
          depth += 1
        elsif c == ']'
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
      nil
    end

    private def split_top_level(text : String, delimiter : Char) : Array(String)
      parts = [] of String
      start = 0
      depth = 0
      quote : Char? = nil
      escaped = false

      text.each_char_with_index do |char, index|
        if quote
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
          next
        end

        case char
        when '\'', '"', '`'
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        else
          if char == delimiter && depth == 0
            parts << text[start...index].strip
            start = index + 1
          end
        end
      end

      parts << text[start..-1].strip
      parts.reject(&.empty?)
    end

    private def skip_top_level_to_comma(body : String, start : Int32) : Int32
      depth = 0
      i = start
      n = body.size
      while i < n
        c = body[i]
        case c
        when '\'', '"', '`'
          quote = c
          i += 1
          while i < n && body[i] != quote
            i += body[i] == '\\' ? 2 : 1
          end
          i += 1
          next
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1
          return i if depth < 0
        when ','
          return i if depth == 0
        else
          # nothing
        end
        i += 1
      end
      i
    end

    private def extract_identifier(value : String) : String?
      v = value.strip
      return if v.empty?
      if m = v.match(/\A([A-Za-z_$][\w$]*)\z/)
        return m[1]
      end
      nil
    end

    private def flatten_router(router : Router, prefix_dotted : String, routers : Hash(RouterKey, Router), procedures : Hash(RouterKey, Procedure), procedures_by_name : Hash(String, Procedure), url_prefix : String, result : Array(Endpoint), visited : Set(RouterKey))
      current_key = router_key(router)
      return if visited.includes?(current_key)
      visited.add(current_key)

      flatten_body(router.body, prefix_dotted, router.base_path, router.file, router.line,
        routers, procedures, procedures_by_name, url_prefix, result, visited)

      visited.delete(current_key)
    end

    # Walk one router-map body (the `{ ... }` content). Each value is a child
    # router (named, inline `router({...})`, or a plain `{ ... }` nested map
    # — tRPC v11), a named procedure, or an inline procedure.
    private def flatten_body(body : String, prefix_dotted : String, base_path : String, file : String, base_line : Int32, routers : Hash(RouterKey, Router), procedures : Hash(RouterKey, Procedure), procedures_by_name : Hash(String, Procedure), url_prefix : String, result : Array(Endpoint), visited : Set(RouterKey))
      base = url_prefix.empty? ? "/" : url_prefix.chomp('/')

      each_top_level_kv(body) do |key, value, value_line|
        next if key.empty?
        child_prefix = prefix_dotted.empty? ? key : "#{prefix_dotted}.#{key}"
        line = base_line + value_line - 1

        if ident = extract_identifier(value)
          if child = routers[router_key(base_path, ident)]?
            flatten_router(child, child_prefix, routers, procedures, procedures_by_name, url_prefix, result, visited)
            next
          end

          # Procedure referenced by name (modular layout: `createDocument:
          # createDocumentRoute`). Resolve to its cross-file definition.
          if proc = procedures[router_key(base_path, ident)]? || procedures_by_name[ident]?
            emit_procedure(proc.value, proc.method, "#{base}/#{child_prefix}", proc.file, proc.line, result)
            next
          end
        end

        # Inline nested router: `key: router({...})` / `t.router({...})`.
        if inner = inline_router_body(value)
          flatten_body(inner, child_prefix, base_path, file, line,
            routers, procedures, procedures_by_name, url_prefix, result, visited)
          next
        end

        # Plain-object nested router (tRPC v11): `key: { sub: proc, ... }`.
        if value.lstrip.starts_with?("{") && (inner = brace_inner(value))
          flatten_body(inner, child_prefix, base_path, file, line,
            routers, procedures, procedures_by_name, url_prefix, result, visited)
          next
        end

        # Inline procedure.
        method = procedure_method(value)
        next unless method
        emit_procedure(value, method, "#{base}/#{child_prefix}", file, line, result)
      end
    end

    private def emit_procedure(value : String, method : String, url : String, file : String, line : Int32, result : Array(Endpoint))
      endpoint = Endpoint.new(url, method)
      endpoint.details = Details.new(PathInfo.new(file, line))
      attach_input_params(value, method, endpoint)
      attach_procedure_callees(value, file, line, endpoint) if callees_needed?
      result << endpoint
    end

    # `key: router({...})` / `key: t.router({...})` / `createTRPCRouter({...})`
    # — return the inner map body, or nil when the value isn't an inline
    # router call (anchored so a `router(` buried in a resolver body of an
    # inline procedure never matches).
    private def inline_router_body(value : String) : String?
      stripped = value.lstrip
      m = stripped.match(/\A(?:[\w$]+\s*\.\s*)?(?:router|createTRPCRouter)\s*\(\s*\{/)
      return unless m
      brace_open = (m.end(0) || 0) - 1
      close = Noir::JSRouteExtractor.find_matching_brace(stripped, brace_open)
      return unless close
      stripped[(brace_open + 1)...close]
    end

    private def brace_inner(value : String) : String?
      stripped = value.lstrip
      open = stripped.index('{')
      return unless open
      close = Noir::JSRouteExtractor.find_matching_brace(stripped, open)
      return unless close
      stripped[(open + 1)...close]
    end

    private def procedure_method(value : String) : String?
      # tRPC subscriptions ride the WebSocket link; map them to the
      # AsyncAPI `SUBSCRIBE` verb the optimizer allow-lists, since
      # plain `WS` would be normalized down to `GET`.
      return "SUBSCRIBE" if value.match(/\.\s*subscription\s*\(/)
      return "POST" if value.match(/\.\s*mutation\s*\(/)
      return "GET" if value.match(/\.\s*query\s*\(/)
      nil
    end

    private def attach_procedure_callees(value : String, file_path : String, procedure_line : Int32, endpoint : Endpoint)
      resolver = procedure_resolver_body(value)
      return unless resolver

      body, relative_line = resolver
      Noir::JSCalleeExtractor.callees_for_function_body(
        body,
        file_path,
        procedure_line + relative_line - 1,
        language: javascript_source_language(file_path)
      ).each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
      end
    end

    private def procedure_resolver_body(value : String) : Tuple(String, Int32)?
      if resolver_match = value.match(/\.\s*(?:query|mutation|subscription)\s*\(/)
        open_paren = (resolver_match.end(0) || 0) - 1
        close_paren = Noir::JSRouteExtractor.find_matching_paren(value, open_paren)
        return unless close_paren

        resolver_source = value[(open_paren + 1)...close_paren]
        line = value[0, open_paren + 1].count('\n') + 1
        arrow_function_body(resolver_source, line) || function_expression_body(resolver_source, line)
      end
    end

    private def arrow_function_body(source : String, start_line : Int32) : Tuple(String, Int32)?
      arrow = source.index("=>")
      return unless arrow

      after_arrow = source[(arrow + 2)..].strip
      line = start_line + source[0, arrow + 2].count('\n')
      if after_arrow.starts_with?("{")
        if close = Noir::JSRouteExtractor.find_matching_brace(after_arrow, 0)
          return {after_arrow[1...close], line}
        end
      end

      {after_arrow, line}
    end

    private def function_expression_body(source : String, start_line : Int32) : Tuple(String, Int32)?
      if match = source.match(/\bfunction\b[^{]*\{/)
        open_brace = (match.end(0) || 0) - 1
        if close = Noir::JSRouteExtractor.find_matching_brace(source, open_brace)
          line = start_line + source[0, open_brace + 1].count('\n')
          return {source[(open_brace + 1)...close], line}
        end
      end
    end

    private def attach_input_params(value : String, method : String, endpoint : Endpoint)
      param_type = method == "POST" ? "body" : "query"

      input_body = procedure_input_body(value)
      return unless input_body

      # Shallow z.object({...}) — pull top-level field names. Deeper schemas
      # are intentionally skipped; the issue calls deep parsing out as the
      # hardest piece and we only need leaf field names for the common case.
      if obj_match = input_body.match(/z\.object\s*\(\s*\{/)
        brace_end = obj_match.end(0) || 0
        if brace_end > 0
          brace_open = brace_end - 1
          if close_brace = Noir::JSRouteExtractor.find_matching_brace(input_body, brace_open)
            schema = input_body[(brace_open + 1)...close_brace]
            extract_schema_fields(schema).each do |name|
              next if name.empty? || name == "z"
              unless endpoint.params.any? { |p| p.name == name && p.param_type == param_type }
                endpoint.push_param(Param.new(name, "", param_type))
              end
            end
            return
          end
        end
      end

      # Fallback: opaque schema, still expose the input slot.
      unless endpoint.params.any? { |p| p.name == "input" && p.param_type == param_type }
        endpoint.push_param(Param.new("input", "", param_type))
      end
    end

    private def procedure_input_body(value : String) : String?
      if input_match = value.match(/\.\s*input\s*\(/)
        open_paren_end = input_match.end(0) || 0
        return if open_paren_end == 0
        open_paren = open_paren_end - 1
        close_paren = Noir::JSRouteExtractor.find_matching_paren(value, open_paren)
        return unless close_paren

        return value[(open_paren + 1)...close_paren]
      end

      v9_procedure_input_body(value)
    end

    private def v9_procedure_input_body(value : String) : String?
      if call_match = value.match(/\.\s*(?:query|mutation|subscription)\s*\(/)
        open_paren = (call_match.end(0) || 0) - 1
        close_paren = Noir::JSRouteExtractor.find_matching_paren(value, open_paren)
        return unless close_paren

        args = split_top_level(value[(open_paren + 1)...close_paren], ',')
        return unless args.size >= 2

        options = args[1].strip
        return unless options.starts_with?("{")

        close_brace = Noir::JSRouteExtractor.find_matching_brace(options, 0)
        return unless close_brace

        input_property_value(options[1...close_brace])
      end
    end

    private def input_property_value(options_body : String) : String?
      options_body.scan(/(?:\A|,)\s*input\s*:/m) do |match|
        value_start = match.end(0) || 0
        value_end = skip_top_level_to_comma(options_body, value_start)
        return options_body[value_start...value_end].strip
      end

      nil
    end

    private def extract_schema_fields(schema : String) : Array(String)
      fields = [] of String
      depth = 0
      i = 0
      n = schema.size
      key_start = -1

      while i < n
        c = schema[i]
        case c
        when '\'', '"', '`'
          quote = c
          i += 1
          while i < n && schema[i] != quote
            i += schema[i] == '\\' ? 2 : 1
          end
          i += 1
          next
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1
        end

        if depth == 0
          if key_start < 0 && (c.ascii_letter? || c == '_' || c == '$')
            key_start = i
          elsif key_start >= 0 && !(c.ascii_alphanumeric? || c == '_' || c == '$')
            name = schema[key_start...i]
            # Only emit when followed (after whitespace) by `:` — that's how
            # we distinguish a property key from any other identifier left
            # at depth 0 by oddly formatted schemas.
            j = i
            while j < n && schema[j].whitespace?
              j += 1
            end
            fields << name if j < n && schema[j] == ':'
            key_start = -1
          end
        else
          key_start = -1
        end

        i += 1
      end

      fields
    end
  end
end
