require "../../engines/scala_engine"

module Analyzer::Scala
  class Http4s < ScalaEngine
    HTTP_METHODS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]

    def analyze_file(path : String) : Array(Endpoint)
      content = File.read(path)
      extract_routes_from_content(path, content, any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?))
    end

    private def extract_routes_from_content(path : String, content : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = content.split('\n')

      routes_names = collect_routes_bindings(content)
      mount_prefixes = collect_mount_prefixes(content, routes_names)

      current_routes_name : String? = nil

      i = 0
      while i < lines.size
        raw = lines[i]
        stripped = scala_code_line(raw)
        trimmed = stripped.strip

        if m = stripped.match(/\b(?:val|def|lazy\s+val)\s+(\w+)\s*(?::[^=]*?)?=\s*HttpRoutes\.of\b/)
          current_routes_name = m[1]
        end

        if case_line?(trimmed)
          header, end_index = collect_case_header(lines, i)
          if data = parse_case_header(header)
            method, segments, path_params, query_params, binding_name = data
            full_path = build_full_path(segments, current_routes_name, mount_prefixes)
            endpoint = Endpoint.new(full_path, method, [] of Param, Details.new(PathInfo.new(path, i + 1)))

            path_params.each do |name|
              unless endpoint.params.any? { |p| p.name == name && p.param_type == "path" }
                endpoint.push_param(Param.new(name, "", "path"))
              end
            end

            query_params.each do |name|
              unless endpoint.params.any? { |p| p.name == name && p.param_type == "query" }
                endpoint.push_param(Param.new(name, "", "query"))
              end
            end

            body_text = extract_case_body(lines, end_index)
            if binding_name
              if body_match = body_text.match(/#{Regex.escape(binding_name)}\s*\.\s*as\s*\[\s*([^\]\s]+)\s*\]/)
                endpoint.push_param(Param.new("body", body_match[1], "json"))
              end
            end

            if include_callee && !body_text.empty?
              callees = Noir::ScalaCalleeExtractor.callees_for_body(body_text, path, i + 1)
              attach_scala_callees(endpoint, callees)
            end

            endpoints << endpoint
          end

          i = end_index + 1
          next
        end

        i += 1
      end

      endpoints
    end

    private def case_line?(trimmed : String) : Bool
      return false unless trimmed.starts_with?("case ")
      return false unless trimmed.includes?("->")
      trimmed =~ /->\s*Root\b/ ? true : false
    end

    # Join continuation lines until we find the `=>` that ends the case pattern.
    private def collect_case_header(lines : Array(String), start : Int32) : Tuple(String, Int32)
      buffer = String.build do |io|
        idx = start
        while idx < lines.size
          stripped = scala_code_line(lines[idx])
          io << stripped
          io << ' '
          if stripped.includes?("=>")
            return {buffer_to_header(io.to_s), idx}
          end
          idx += 1
        end
      end
      {buffer_to_header(buffer), lines.size - 1}
    end

    private def buffer_to_header(text : String) : String
      arrow = text.index("=>")
      arrow ? text[0...arrow] : text
    end

    # Parse a joined case header like:
    #   case req @ POST -> Root / "users" / IntVar(id) :? FooMatcher(foo) +& BarMatcher(bar)
    # Returns: method, path segments, path params, query params, binding name (or nil)
    private def parse_case_header(header : String)
      cleaned = header.strip
      return nil unless cleaned.starts_with?("case ")
      body = cleaned[("case ".size)..].strip

      binding_name : String? = nil
      if at_match = body.match(/^(\w+)\s*@\s*/)
        binding_name = at_match[1]
        body = body[at_match.end(0).not_nil!..]
      end

      method_match = body.match(/^(?:\(\s*)?([A-Z]+)(?:\s*\|\s*[A-Z]+)*(?:\s*\))?\s*->\s*Root\b/)
      return nil unless method_match
      method = method_match[1]
      return nil unless HTTP_METHODS.includes?(method)

      remainder = body[method_match.end(0).not_nil!..].strip

      path_part = remainder
      query_part = ""
      if qidx = remainder.index(":?")
        path_part = remainder[0...qidx]
        query_part = remainder[(qidx + 2)..]
      end

      segments, path_params = parse_segments(path_part)
      query_params = parse_query_matchers(query_part)

      {method, segments, path_params, query_params, binding_name}
    end

    private def parse_segments(path_part : String) : Tuple(Array(String), Array(String))
      segments = [] of String
      path_params = [] of String

      tokens = path_part.split('/').map(&.strip).reject(&.empty?)
      tokens.each do |tok|
        if literal_match = tok.match(/^"([^"]+)"$/)
          segments << literal_match[1]
        elsif var_match = tok.match(/^\w*Var\s*\(\s*(\w+)\s*\)$/)
          name = var_match[1]
          segments << "{#{name}}"
          path_params << name
        elsif extractor_match = tok.match(/^\w+\s*\(\s*(\w+)\s*\)$/)
          name = extractor_match[1]
          segments << "{#{name}}"
          path_params << name
        elsif ident_match = tok.match(/^(\w+)$/)
          name = ident_match[1]
          segments << "{#{name}}"
          path_params << name
        else
          # Unrecognized extractor; skip but continue parsing other segments.
        end
      end

      {segments, path_params}
    end

    private def parse_query_matchers(query_part : String) : Array(String)
      params = [] of String
      return params if query_part.empty?

      query_part.scan(/(\w+)\s*\(\s*(\w+)\s*\)/) do |m|
        matcher = m[1]
        name = m[2]
        next unless matcher.ends_with?("Matcher") || matcher.ends_with?("QueryParamDecoderMatcher") || matcher.includes?("QueryParam")
        params << name unless params.includes?(name)
      end

      params
    end

    private def build_full_path(segments : Array(String), routes_name : String?, mount_prefixes : Hash(String, String)) : String
      route_path = segments.empty? ? "/" : "/" + segments.join("/")
      if routes_name && (prefix = mount_prefixes[routes_name]?)
        normalized = "#{prefix.rstrip('/')}#{route_path == "/" ? "" : route_path}"
        normalized = "/" if normalized.empty?
        normalized = "/#{normalized}" unless normalized.starts_with?("/")
        return normalized.gsub(%r{/+}, "/")
      end
      route_path
    end

    private def collect_routes_bindings(content : String) : Set(String)
      names = Set(String).new
      content.scan(/\b(?:val|def|lazy\s+val)\s+(\w+)\s*(?::[^=]*?)?=\s*HttpRoutes\.of\b/) do |m|
        names << m[1]
      end
      names
    end

    private def collect_mount_prefixes(content : String, routes_names : Set(String)) : Hash(String, String)
      prefixes = {} of String => String
      content.scan(/"(\/[^"]*)"\s*->\s*(\w+)/) do |m|
        prefix = m[1]
        name = m[2]
        next unless routes_names.includes?(name)
        prefixes[name] = prefix unless prefixes.has_key?(name)
      end
      prefixes
    end

    # Pull case body text from the line after the `=>` until the next `case ` at the same level
    # or the close of the enclosing brace. Used for body-type and callee extraction.
    private def extract_case_body(lines : Array(String), header_end_index : Int32) : String
      body_lines = [] of String
      tail = lines[header_end_index]? || ""
      if arrow = tail.index("=>")
        body_lines << tail[(arrow + 2)..]
      end

      idx = header_end_index + 1
      brace_depth = 0
      while idx < lines.size
        line = lines[idx]
        stripped = scala_code_line(line)
        trimmed = stripped.strip

        if brace_depth <= 0 && (trimmed.starts_with?("case ") || trimmed == "}")
          break
        end

        body_lines << line
        brace_depth += stripped.count('{') - stripped.count('}')
        break if brace_depth < 0
        idx += 1
      end

      body_lines.join("\n")
    end
  end
end
