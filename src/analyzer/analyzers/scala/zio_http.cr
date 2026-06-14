require "../../engines/scala_engine"

module Analyzer::Scala
  class ZioHttp < ScalaEngine
    HTTP_METHODS   = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]
    MATCHER_IDENTS = %w[int long string uuid boolean bool trailing]

    def analyze_file(path : String) : Array(Endpoint)
      content = File.read(path)
      extract_routes_from_content(path, content, any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?))
    end

    # Extract routes from ZIO HTTP DSL:
    #   Method.GET / "users" / int("id") -> handler { (id: Int, req: Request) => ... }
    private def extract_routes_from_content(path : String, content : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = content.split('\n')
      code_lines = scala_code_lines(content)

      lines.each_with_index do |_line, index|
        stripped = code_lines[index]? || ""

        offset = 0
        while m = stripped.match(/(?<![.\w])Method\.([A-Z]+)/, offset)
          method = m[1]
          method_end = m.end(0) || 0
          offset = method_end

          next unless HTTP_METHODS.includes?(method)

          rest = stripped[method_end..]
          arrow_idx = rest.index("->")
          path_segments_str = arrow_idx ? rest[0...arrow_idx] : rest

          route_path, path_params = zio_path_from_segments(path_segments_str)

          endpoint = create_endpoint(route_path, method, path, index + 1)
          path_params.each do |name|
            endpoint.push_param(Param.new(name, "", "path"))
          end

          if arrow_idx
            block_info = extract_handler_block(lines, index)
            if block_info
              block_content, block_start = block_info
              extract_params_from_block(endpoint, block_content)
              if include_callee
                callees = Noir::ScalaCalleeExtractor.callees_for_body(block_content, path, block_start)
                attach_scala_callees(endpoint, callees)
              end
            end
          else
            # Declarative `Endpoint(Method.X / …)` form: query/header/body come
            # from the codec chain (`.query(HttpCodec.query[T]("n"))`, `.in[T]`)
            # that follows on continuation lines, not from a handler block.
            extract_declarative_params(endpoint, collect_declarative_chain(code_lines, index))
          end

          endpoints << endpoint
        end
      end

      endpoints
    end

    # Parse a ZIO HTTP path expression like:
    #   / "api" / "v1" / "items" / int("id")
    # into a normalized URL path and the list of path parameter names.
    private def zio_path_from_segments(segments_str : String) : Tuple(String, Array(String))
      segments = [] of String
      params = [] of String

      s = segments_str
      i = 0
      while i < s.size
        ch = s[i]
        if ch == '/' || ch == ' ' || ch == '\t'
          i += 1
        elsif ch == '"'
          close = s.index('"', i + 1)
          break unless close
          literal = s[(i + 1)...close]
          literal.split('/').each do |part|
            segments << part unless part.empty?
          end
          i = close + 1
        elsif ch.ascii_letter? || ch == '_'
          start = i
          while i < s.size && (s[i].ascii_alphanumeric? || s[i] == '_' || s[i] == '.')
            i += 1
          end
          ident = s[start...i]

          j = i
          while j < s.size && (s[j] == ' ' || s[j] == '\t')
            j += 1
          end

          if j < s.size && s[j] == '('
            paren_end = s.index(')', j)
            break unless paren_end
            inner = s[(j + 1)...paren_end]
            if name_match = inner.match(/"([^"]+)"/)
              name = name_match[1]
            else
              name = default_param_name(params.size)
            end
            if matcher_ident?(ident)
              segments << "{#{name}}"
              params << name
            end
            i = paren_end + 1
          else
            if matcher_ident?(ident)
              name = default_param_name(params.size)
              segments << "{#{name}}"
              params << name
            end
          end
        elsif ch == ')'
          # A bare `)` (matchers consume their own parens) closes the enclosing
          # `Endpoint(Method.GET / …)` — the path ends here. Without this the
          # trailing builder, e.g. `.out[Int]`, gets mis-parsed (the `Int` in
          # `[Int]` would register a phantom `{id2}` path param).
          break
        else
          i += 1
        end
      end

      route = segments.empty? ? "/" : "/" + segments.join("/")
      {route, params}
    end

    private def matcher_ident?(ident : String) : Bool
      base = ident.includes?('.') ? ident.split('.').last : ident
      MATCHER_IDENTS.includes?(base.downcase)
    end

    # The codec chain of a declarative endpoint: the route line plus the
    # following `.`-prefixed continuation lines (`.query(...)`, `.header(...)`,
    # `.out[...]`).
    private def collect_declarative_chain(code_lines : Array(String), index : Int32) : String
      parts = [code_lines[index]? || ""]
      idx = index + 1
      while idx < code_lines.size
        line = code_lines[idx]? || ""
        break unless line.lstrip.starts_with?(".")
        parts << line
        idx += 1
      end
      parts.join("\n")
    end

    private def extract_declarative_params(endpoint : Endpoint, chain : String)
      chain.scan(/\bquery\s*\[[^\]]*\]\s*\(\s*"([^"]+)"\s*\)/) do |m|
        name = m[1]
        unless endpoint.params.any? { |p| p.name == name && p.param_type == "query" }
          endpoint.push_param(Param.new(name, "", "query"))
        end
      end

      chain.scan(/\bheader\s*\[[^\]]*\]\s*\(\s*"([^"]+)"\s*\)/) do |m|
        name = m[1]
        unless endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
          endpoint.push_param(Param.new(name, "", "header"))
        end
      end
    end

    private def default_param_name(index : Int32) : String
      index == 0 ? "id" : "id#{index + 1}"
    end

    # Find the handler block (`handler { ... }`) associated with a Method.X route.
    # ZIO HTTP writes `-> handler { ... }` or `-> handler(...)` on the same line as
    # the route. To avoid bleeding state from neighbouring routes we only inspect
    # the route line itself (a one-line `handler(...)` has no body to look into).
    private def extract_handler_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      structural = scala_structural_line(lines[start_index])
      opening_match = structural.match(/(?<![.\w])handler\s*\{/) || structural.match(/->\s*\{/)
      return unless opening_match
      opening_brace_in_structural = (opening_match.end(0) || 1) - 1
      block = extract_scala_brace_block_with_end_at(lines, start_index, opening_brace_in_structural)
      return unless block
      {block[0], block[1]}
    end

    private def extract_params_from_block(endpoint : Endpoint, block : String)
      # Request body: req.body.to[Type] / request.body.to[Type]
      if entity_match = block.match(/(?:req|request)\.body\.to\[([^\]]+)\]/)
        endpoint.push_param(Param.new("body", entity_match[1], "json"))
      elsif block.match(/(?:req|request)\.body(?:\.as[A-Za-z_]\w*|\.asString|\.asArray|\.asMultipart)?/)
        unless endpoint.params.any? { |p| p.name == "body" }
          endpoint.push_param(Param.new("body", "", "json"))
        end
      end

      # Query parameters: req.url.queryParam("name"), req.queryParam("name"), queryParams("name")
      block.scan(/queryParam(?:s|ToList|OrElse)?\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        name = match[1]
        unless endpoint.params.any? { |p| p.name == name && p.param_type == "query" }
          endpoint.push_param(Param.new(name, "", "query"))
        end
      end

      # Headers: req.headers.get("X-Foo"), req.headers.header("X-Foo")
      block.scan(/headers\.(?:get|header|rawHeader)\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        name = match[1]
        unless endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
          endpoint.push_param(Param.new(name, "", "header"))
        end
      end

      # Header objects read off the request: a bare reference like
      # `req.header(Header.Authorization)`. Skip construction/builder forms —
      # `Header.ContentType(MediaType…)` or `Header.ContentDisposition.attachment(…)`
      # — which set RESPONSE headers, not request params (the `(?![\w(.])` guard).
      block.scan(/Header\.([A-Z][A-Za-z0-9]+)(?![\w(.])/) do |match|
        typed_name = humanize_header(match[1])
        unless endpoint.params.any? { |p| p.name == typed_name && p.param_type == "header" }
          endpoint.push_param(Param.new(typed_name, "", "header"))
        end
      end
    end

    # Convert ZIO HTTP typed header names like `XRequestId` to canonical `X-Request-Id`.
    private def humanize_header(name : String) : String
      parts = [] of String
      buffer = String::Builder.new
      name.each_char do |ch|
        if ch.uppercase? && buffer.bytesize > 0
          parts << buffer.to_s
          buffer = String::Builder.new
        end
        buffer << ch
      end
      parts << buffer.to_s if buffer.bytesize > 0
      parts.join("-")
    end

    private def create_endpoint(path : String, method : String, source : String, line_number : Int32)
      details = Details.new(PathInfo.new(source, line_number))
      Endpoint.new(path, method, [] of Param, details)
    end
  end
end
