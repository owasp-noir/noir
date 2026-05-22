require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Typescript
  class TRPC < Analyzer::Javascript::JavascriptEngine
    DEFAULT_PREFIX = "/api/trpc"

    private struct Router
      getter name : String
      getter body : String
      getter file : String
      getter line : Int32

      def initialize(@name : String, @body : String, @file : String, @line : Int32)
      end
    end

    def analyze
      result = [] of Endpoint
      routers = Hash(String, Router).new
      routers_mu = Mutex.new
      prefix_mu = Mutex.new
      url_prefix = DEFAULT_PREFIX

      parallel_file_scan([".js", ".ts", ".jsx", ".tsx", ".cts", ".mts", ".cjs", ".mjs"]) do |path|
        begin
          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            raw = file.gets_to_end
            content = Noir::JSRouteExtractor.strip_js_comments(raw)
            collected = collect_routers(content, path)
            unless collected.empty?
              routers_mu.synchronize do
                collected.each { |r| routers[r.name] = r }
              end
            end
            if found = extract_prefix(content)
              prefix_mu.synchronize do
                url_prefix = found
              end
            end
          end
        rescue e
          logger.debug "Error analyzing tRPC file #{path}: #{e.message}"
        end
        nil
      end

      return result if routers.empty?

      used_as_child = Set(String).new
      routers.each_value do |router|
        each_top_level_kv(router.body) do |_key, value, _value_line|
          ident = extract_identifier(value)
          used_as_child.add(ident) if ident && routers.has_key?(ident)
        end
      end

      roots = routers.values.reject { |r| used_as_child.includes?(r.name) }
      roots = routers.values if roots.empty?

      roots.each do |root|
        flatten_router(root, "", routers, url_prefix, result, Set(String).new)
      end

      result
    end

    private def collect_routers(content : String, path : String) : Array(Router)
      collected = [] of Router
      # Capture `(export )? (const|let|var) NAME = <prefix>?(router|createTRPCRouter)({...})`.
      # Prefix tolerates `t.router(`, `initTRPC.create().router(`, `_.router(` etc.
      pattern = /\b(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:[\w$]+\s*(?:\(\s*\))?\s*\.\s*)?(?:router|createTRPCRouter)\s*\(\s*\{/

      content.scan(pattern) do |match|
        match_start = match.begin(0) || 0
        match_end = match.end(0) || 0
        next if match_end == 0

        brace_open = match_end - 1
        next unless content[brace_open]? == '{'

        brace_close = Noir::JSRouteExtractor.find_matching_brace(content, brace_open)
        next unless brace_close

        body = content[(brace_open + 1)...brace_close]
        line = content[0, match_start].count('\n') + 1
        collected << Router.new(match[1], body, path, line)
      end

      collected
    end

    private def extract_prefix(content : String) : String?
      # Explicit endpoint option in fetch/openapi handlers.
      if m = content.match(/endpoint\s*:\s*['"`]([^'"`]+)['"`]/)
        return m[1]
      end

      # Express/Koa-style mounting: `app.use('/api/trpc', trpcExpress.createExpressMiddleware(...))`.
      if m = content.match(/\.\s*use\s*\(\s*['"`]([^'"`]+)['"`]\s*,\s*[^)]*?(?:trpcExpress\.createExpressMiddleware|createExpressMiddleware|createKoaMiddleware)/m)
        return m[1]
      end

      # Fastify plugin: `fastify.register(fastifyTRPCPlugin, { prefix: '/api/trpc' })`.
      if m = content.match(/(?:fastifyTRPCPlugin|fastifyTRPC)\b[^)]*?prefix\s*:\s*['"`]([^'"`]+)['"`]/m)
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

    private def flatten_router(router : Router, prefix_dotted : String, routers : Hash(String, Router), url_prefix : String, result : Array(Endpoint), visited : Set(String))
      return if visited.includes?(router.name)
      visited.add(router.name)

      each_top_level_kv(router.body) do |key, value, value_line|
        next if key.empty?

        if ident = extract_identifier(value)
          if child = routers[ident]?
            child_prefix = prefix_dotted.empty? ? key : "#{prefix_dotted}.#{key}"
            flatten_router(child, child_prefix, routers, url_prefix, result, visited)
            next
          end
        end

        method = procedure_method(value)
        next unless method

        dotted = prefix_dotted.empty? ? key : "#{prefix_dotted}.#{key}"
        base = url_prefix.empty? ? "/" : url_prefix.chomp('/')
        url = "#{base}/#{dotted}"
        endpoint = Endpoint.new(url, method)
        endpoint.details = Details.new(PathInfo.new(router.file, router.line))

        attach_input_params(value, method, endpoint)
        procedure_line = router.line + value_line - 1
        attach_procedure_callees(value, router.file, procedure_line, endpoint) if callees_needed?

        result << endpoint
      end

      visited.delete(router.name)
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
        return arrow_function_body(resolver_source, line) || function_expression_body(resolver_source, line)
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

      # Locate the .input(...) call; without one, every method exposes the
      # raw `input` slot — GETs serialize it as ?input=, mutations send the
      # body verbatim. We still surface that so consumers see the contract.
      input_match = value.match(/\.\s*input\s*\(/)
      unless input_match
        return
      end

      open_paren_end = input_match.end(0) || 0
      return if open_paren_end == 0
      open_paren = open_paren_end - 1
      close_paren = Noir::JSRouteExtractor.find_matching_paren(value, open_paren)
      return unless close_paren

      input_body = value[(open_paren + 1)...close_paren]

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
