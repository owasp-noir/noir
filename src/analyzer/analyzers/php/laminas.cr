require "../../engines/php_engine"

module Analyzer::Php
  class Laminas < PhpEngine
    HTTP_METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]

    private struct PhpArrayEntry
      getter key, value, array_body

      def initialize(@key : String, @value : String?, @array_body : String?)
      end
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".php")

      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        next unless laminas_relevant?(path, content)

        endpoints.concat(analyze_config_routes(path, content))
        endpoints.concat(analyze_programmatic_routes(path, content, include_callee))
      end

      dedup_endpoints(endpoints)
    end

    private def laminas_relevant?(path : String, content : String) : Bool
      return true if path.includes?("/config/") && (content.includes?("'router'") || content.includes?("\"router\""))
      return true if content.includes?("Laminas\\") || content.includes?("Zend\\") || content.includes?("Mezzio\\")
      return true if content.includes?("RouteStackInterface")
      !!content.match(/->(?:get|post|put|patch|delete|options|head|any|route)\s*\(\s*['"][^'"]+['"]/i)
    end

    private def analyze_config_routes(path : String, content : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      route_blocks(content).each do |block|
        endpoints.concat(parse_routes_block(block, "", ["GET"], path))
      end
      endpoints
    end

    private def route_blocks(content : String) : Array(String)
      blocks = [] of String
      offset = 0

      while match = content.match(/['"]routes['"]\s*=>\s*(?:\[|array\s*\()/i, offset)
        open_pos = match[0].ends_with?("[") ? match.end(0) - 1 : match.end(0) - 1
        close_pos = find_matching_delimiter(content, open_pos)
        if close_pos
          blocks << content[(open_pos + 1)...close_pos]
          offset = close_pos + 1
        else
          offset = match.end(0)
        end
      end

      blocks
    end

    private def parse_routes_block(block : String, prefix : String, inherited_methods : Array(String), path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))

      parse_top_level_entries(block).each do |route_entry|
        body = route_entry.array_body
        next unless body

        entry_info = route_entry_info(body)
        methods = entry_info[:methods].empty? ? inherited_methods : entry_info[:methods]
        child_routes = entry_info[:child_routes]

        full_path = prefix
        if route_path = entry_info[:route_path]
          full_path = entry_info[:hostname] ? prefix : build_full_path(prefix, route_path)

          if entry_info[:may_terminate] && (!entry_info[:hostname] || full_path.empty?)
            endpoint_path = full_path.empty? ? "/" : full_path
            params = extract_laminas_path_params(endpoint_path, entry_info[:constraints])
            methods.each do |method|
              endpoints << Endpoint.new(endpoint_path, method, params, details.dup)
            end
          end
        end

        if child_routes
          endpoints.concat(parse_routes_block(child_routes, full_path, methods, path))
        end
      end

      endpoints
    end

    private def route_entry_info(body : String) : NamedTuple(
      route_path: String?,
      methods: Array(String),
      constraints: Hash(String, String),
      child_routes: String?,
      hostname: Bool,
      may_terminate: Bool)
      entries = parse_top_level_entries(body)
      options_body = array_entry(entries, "options")
      options_entries = options_body ? parse_top_level_entries(options_body) : [] of PhpArrayEntry

      type_value = raw_entry(entries, "type") || ""
      nested_route_info = array_entry(entries, "route").try { |route_body| route_entry_info(route_body) }
      hostname = type_value.downcase.includes?("hostname") || (nested_route_info ? nested_route_info[:hostname] : false)

      route = string_entry(options_entries, "route") || string_entry(entries, "route")
      regex_spec = type_value.downcase.includes?("regex") ? string_entry(options_entries, "spec") : nil
      normalized_route =
        if route
          normalize_laminas_route_path(route, hostname)
        elsif regex_spec
          normalize_laminas_regex_spec(regex_spec)
        elsif nested_route_info
          nested_route_info[:route_path]
        end

      methods = extract_methods_from_entries(options_entries)
      methods = extract_methods_from_entries(entries) if methods.empty?
      methods = nested_route_info[:methods] if methods.empty? && nested_route_info

      constraints = extract_constraints(options_entries)
      constraints = nested_route_info[:constraints] if constraints.empty? && nested_route_info
      child_routes = array_entry(entries, "child_routes")

      may_terminate = !type_value.downcase.includes?("part")
      if value = raw_entry(entries, "may_terminate")
        may_terminate = !value.downcase.includes?("false")
      end

      {
        route_path:    normalized_route,
        methods:       methods,
        constraints:   constraints,
        child_routes:  child_routes,
        hostname:      hostname,
        may_terminate: may_terminate,
      }
    end

    private def analyze_programmatic_routes(path : String, content : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))
      working_content = strip_php_comments(content)

      # The path literal must stay on one line and contain no quotes. The
      # earlier `(.*?)\3` spanned newlines under DOTALL, so an unrelated
      # `$obj->get('x')` (no trailing comma) backtracked until it found a
      # far-off quote+comma, surfacing multi-line code as a bogus route
      # (e.g. CakePHP controllers in cakesandbox, koel request objects).
      verb_regex = /(\$\w+|\$this->\w+)->(get|post|put|patch|delete|options|head|any)\s*\(\s*(['"])([^'"\r\n]*?)\3\s*,/im
      pos = 0
      while match = working_content.match(verb_regex, pos)
        match_text = match[0]
        match_start = working_content.index(match_text, pos)
        break unless match_start

        route_path = normalize_laminas_route_path(match[4])
        methods = match[2].downcase == "any" ? HTTP_METHODS : [match[2].upcase]
        after_args = match_start + match_text.size
        handler_body, next_pos, body_start_line = extract_handler_body_with_end(working_content, after_args)

        params = extract_laminas_path_params(route_path)
        params.concat(extract_handler_params(handler_body)) if handler_body
        params = dedup_params(params)

        methods.each do |method|
          endpoint = Endpoint.new(route_path, method, params, details.dup)
          attach_handler_callees(endpoint, handler_body, path, body_start_line) if include_callee
          endpoints << endpoint
        end

        pos = next_pos
      end

      # Single-line, quote-free path only. The old `(.*?)\2` spanned newlines,
      # so Laravel's `$this->route('user')` param helper (no trailing comma)
      # backtracked to a distant quote+comma and surfaced controller code as a
      # 7-method phantom route (koel request objects).
      route_regex = /(\$\w+|\$this->\w+)->route\s*\(\s*(['"])([^'"\r\n]*?)\2\s*,/im
      pos = 0
      while match = working_content.match(route_regex, pos)
        match_text = match[0]
        match_start = working_content.index(match_text, pos)
        break unless match_start

        call_open = working_content.index('(', match_start)
        break unless call_open

        call_close = find_matching_delimiter(working_content, call_open)
        if call_close
          call_content = working_content[(call_open + 1)...call_close]
          route_path = normalize_laminas_route_path(match[3])
          methods = extract_methods_from_route_call(call_content)
          params = extract_laminas_path_params(route_path)

          methods.each do |method|
            endpoints << Endpoint.new(route_path, method, params, details.dup)
          end
          pos = call_close + 1
        else
          pos = match_start + match_text.size
        end
      end

      endpoints
    end

    private def attach_handler_callees(endpoint : Endpoint, body : String?, file_path : String, start_line : Int32?)
      return unless body && start_line

      callees = Noir::PhpCalleeExtractor.callees_for_body(body, file_path, start_line)
      attach_php_callees(endpoint, callees)
    end

    private def extract_handler_body_with_end(content : String, pos : Int32) : Tuple(String?, Int32, Int32?)
      return {nil, pos, nil} unless pos < content.size

      scan_pos = pos
      while scan_pos < content.size && content[scan_pos].ascii_whitespace?
        scan_pos += 1
      end
      return {nil, pos, nil} unless scan_pos < content.size

      closure_regex = /\A(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      match = content[scan_pos..].match(closure_regex)
      return {nil, pos, nil} unless match

      brace_pos = scan_pos + match[0].size - 1
      body_end = find_matching_delimiter(content, brace_pos)
      return {nil, pos, nil} unless body_end

      body_start_line = php_line_number_for_index(content, brace_pos)
      {content[(brace_pos + 1)...body_end], body_end + 1, body_start_line}
    end

    PARAM_PATTERNS = [
      {/->getQueryParams\s*\(\s*\)\s*\[\s*['"]([^'"]+)['"]\s*\]/, "query"},
      {/->getParsedBody\s*\(\s*\)\s*\[\s*['"]([^'"]+)['"]\s*\]/, "form"},
      {/->getUploadedFiles\s*\(\s*\)\s*\[\s*['"]([^'"]+)['"]\s*\]/, "form"},
      {/->getHeaderLine\s*\(\s*['"]([^'"]+)['"]\s*\)/, "header"},
      {/->getHeader\s*\(\s*['"]([^'"]+)['"]\s*\)/, "header"},
      {/->getCookieParams\s*\(\s*\)\s*\[\s*['"]([^'"]+)['"]\s*\]/, "cookie"},
    ]

    private def extract_handler_params(body : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new

      PARAM_PATTERNS.each do |entry|
        pattern, type = entry
        body.scan(pattern) do |match|
          name = match[1]
          key = "#{type}\0#{name}"
          next if seen.includes?(key)

          params << Param.new(name, "", type)
          seen.add(key)
        end
      end

      params
    end

    private def normalize_laminas_route_path(route : String, hostname : Bool = false) : String
      return "" if hostname

      normalized = route.gsub("[", "").gsub("]", "")
      normalized = normalized.gsub(/\{(\w+):[^}]+\}/) { |_| "{#{$~[1]}}" }
      normalized = normalized.gsub(/:([A-Za-z_]\w*)/) { |_| "{#{$~[1]}}" }
      normalized = normalized.gsub(/\{[^A-Za-z_][^}]*\}/, "")
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized = normalized.gsub(/\/+/, "/")
      normalized = normalized.chomp('/') if normalized.size > 1
      normalize_php_interpolation(normalized)
    end

    private def normalize_laminas_regex_spec(spec : String) : String
      normalized = spec.gsub(/%([A-Za-z_]\w*)%/) { |_| "{#{$~[1]}}" }
      normalize_laminas_route_path(normalized)
    end

    private def extract_laminas_path_params(route_path : String, constraints = Hash(String, String).new) : Array(Param)
      params = [] of Param
      seen = Set(String).new

      route_path.scan(/\{([A-Za-z_]\w*)\??\}/) do |match|
        name = match[1]
        next if seen.includes?(name)

        params << Param.new(name, constraints[name]? || "", "path")
        seen.add(name)
      end

      params
    end

    private def extract_constraints(entries : Array(PhpArrayEntry)) : Hash(String, String)
      constraints = {} of String => String
      constraints_body = array_entry(entries, "constraints")
      return constraints unless constraints_body

      parse_top_level_entries(constraints_body).each do |entry|
        if value = entry.value
          constraints[entry.key] = value
        end
      end

      constraints
    end

    private def extract_methods_from_entries(entries : Array(PhpArrayEntry)) : Array(String)
      methods = [] of String
      entries.each do |entry|
        next unless ["verb", "verbs", "method", "methods"].includes?(entry.key.downcase)

        if value = entry.value
          methods.concat(extract_http_methods(value))
        elsif body = entry.array_body
          methods.concat(extract_http_methods(body))
        end
      end
      methods.uniq
    end

    private def extract_http_methods(content : String) : Array(String)
      return HTTP_METHODS if content.match(/HTTP_METHOD_ANY|METHOD_ANY/i)

      methods = [] of String
      content.scan(/['"]?(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)['"]?/i) do |match|
        methods << match[1].upcase
      end
      methods.uniq
    end

    private def extract_methods_from_route_call(call_content : String) : Array(String)
      args = split_top_level_args(call_content)
      method_arg = args[2]?
      return HTTP_METHODS unless method_arg

      stripped = method_arg.strip
      return HTTP_METHODS if stripped.empty? || stripped.downcase == "null"

      methods = extract_http_methods(stripped)
      methods.empty? ? HTTP_METHODS : methods
    end

    private def split_top_level_args(content : String) : Array(String)
      args = [] of String
      start = 0
      i = 0
      depth = 0
      in_string = false
      quote = '\0'
      escaped = false

      while i < content.size
        char = content[i]
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == '\'' || char == '"'
          in_string = true
          quote = char
        elsif char == '[' || char == '(' || char == '{'
          depth += 1
        elsif char == ']' || char == ')' || char == '}'
          depth -= 1 if depth > 0
        elsif char == ',' && depth == 0
          args << content[start...i].strip
          start = i + 1
        end
        i += 1
      end

      args << content[start...content.size].strip if start < content.size
      args
    end

    private def parse_top_level_entries(content : String) : Array(PhpArrayEntry)
      entries = [] of PhpArrayEntry
      pos = 0

      while pos < content.size
        pos = skip_ws_and_commas(content, pos)
        break if pos >= content.size

        key_info = read_php_string(content, pos)
        unless key_info
          pos += 1
          next
        end

        key, after_key = key_info
        pos = skip_ws(content, after_key)
        unless content[pos, 2]? == "=>"
          pos = after_key
          next
        end

        pos = skip_ws(content, pos + 2)
        break if pos >= content.size

        if array_start = array_value_start(content, pos)
          close_pos = find_matching_delimiter(content, array_start)
          unless close_pos
            pos += 1
            next
          end

          entries << PhpArrayEntry.new(key, nil, content[(array_start + 1)...close_pos])
          pos = close_pos + 1
        elsif value_info = read_php_string(content, pos)
          value, after_value = value_info
          entries << PhpArrayEntry.new(key, value, nil)
          pos = after_value
        else
          value, after_value = read_raw_value(content, pos)
          entries << PhpArrayEntry.new(key, value, nil)
          pos = after_value
        end
      end

      entries
    end

    private def array_value_start(content : String, pos : Int32) : Int32?
      return pos if content[pos]? == '['

      if match = content[pos..].match(/\Aarray\s*\(/i)
        return pos + match[0].size - 1
      end

      nil
    end

    private def read_php_string(content : String, pos : Int32) : Tuple(String, Int32)?
      quote = content[pos]?
      return unless quote == '\'' || quote == '"'

      value = String.build do |io|
        i = pos + 1
        escaped = false
        while i < content.size
          char = content[i]
          if escaped
            io << char
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            return {io.to_s, i + 1}
          else
            io << char
          end
          i += 1
        end
      end

      {value, content.size}
    end

    private def read_raw_value(content : String, pos : Int32) : Tuple(String, Int32)
      start = pos
      i = pos
      depth = 0
      in_string = false
      quote = '\0'
      escaped = false

      while i < content.size
        char = content[i]
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == '\'' || char == '"'
          in_string = true
          quote = char
        elsif char == '[' || char == '(' || char == '{'
          depth += 1
        elsif char == ']' || char == ')' || char == '}'
          break if depth == 0
          depth -= 1
        elsif char == ',' && depth == 0
          break
        end
        i += 1
      end

      {content[start...i].strip, i}
    end

    private def find_matching_delimiter(content : String, open_pos : Int32) : Int32?
      open_char = content[open_pos]?
      close_char = case open_char
                   when '[' then ']'
                   when '(' then ')'
                   when '{' then '}'
                   else
                     return
                   end

      stack = [close_char]
      in_string = false
      in_line_comment = false
      in_block_comment = false
      escaped = false
      quote = '\0'
      pos = open_pos + 1

      while pos < content.size
        char = content[pos]
        next_char = content[pos + 1]?

        if in_line_comment
          in_line_comment = false if char == '\n'
        elsif in_block_comment
          if char == '*' && next_char == '/'
            in_block_comment = false
            pos += 1
          end
        elsif in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == '/' && next_char == '/'
          in_line_comment = true
          pos += 1
        elsif char == '/' && next_char == '*'
          in_block_comment = true
          pos += 1
        elsif char == '#'
          in_line_comment = true
        elsif char == '"' || char == '\''
          in_string = true
          quote = char
        elsif char == '['
          stack << ']'
        elsif char == '('
          stack << ')'
        elsif char == '{'
          stack << '}'
        elsif char == stack.last?
          stack.pop
          return pos if stack.empty?
        end

        pos += 1
      end

      nil
    end

    private def strip_php_comments(content : String) : String
      String.build do |io|
        in_string = false
        in_line_comment = false
        in_block_comment = false
        escaped = false
        quote = '\0'
        pos = 0

        while pos < content.size
          char = content[pos]
          next_char = content[pos + 1]?

          if in_line_comment
            if char == '\n'
              in_line_comment = false
              io << char
            else
              io << ' '
            end
          elsif in_block_comment
            if char == '*' && next_char == '/'
              in_block_comment = false
              io << "  "
              pos += 1
            elsif char == '\n'
              io << char
            else
              io << ' '
            end
          elsif in_string
            io << char
            if escaped
              escaped = false
            elsif char == '\\'
              escaped = true
            elsif char == quote
              in_string = false
            end
          elsif char == '/' && next_char == '/'
            in_line_comment = true
            io << "  "
            pos += 1
          elsif char == '/' && next_char == '*'
            in_block_comment = true
            io << "  "
            pos += 1
          elsif char == '#'
            in_line_comment = true
            io << ' '
          elsif char == '"' || char == '\''
            in_string = true
            quote = char
            io << char
          else
            io << char
          end

          pos += 1
        end
      end
    end

    private def skip_ws(content : String, pos : Int32) : Int32
      i = pos
      while i < content.size && content[i].ascii_whitespace?
        i += 1
      end
      i
    end

    private def skip_ws_and_commas(content : String, pos : Int32) : Int32
      i = pos
      while i < content.size && (content[i].ascii_whitespace? || content[i] == ',')
        i += 1
      end
      i
    end

    private def string_entry(entries : Array(PhpArrayEntry), key : String) : String?
      entries.find { |entry| entry.key == key }.try(&.value)
    end

    private def raw_entry(entries : Array(PhpArrayEntry), key : String) : String?
      entries.find { |entry| entry.key == key }.try { |entry| entry.value || entry.array_body }
    end

    private def array_entry(entries : Array(PhpArrayEntry), key : String) : String?
      entries.find { |entry| entry.key == key }.try(&.array_body)
    end

    private def dedup_params(params : Array(Param)) : Array(Param)
      seen = Set(String).new
      params.select do |param|
        key = "#{param.param_type}\0#{param.name}"
        if seen.includes?(key)
          false
        else
          seen.add(key)
          true
        end
      end
    end

    private def dedup_endpoints(endpoints : Array(Endpoint)) : Array(Endpoint)
      seen = Set(String).new
      endpoints.select do |endpoint|
        key = "#{endpoint.method}\0#{endpoint.url}"
        if seen.includes?(key)
          false
        else
          seen.add(key)
          true
        end
      end
    end
  end
end
