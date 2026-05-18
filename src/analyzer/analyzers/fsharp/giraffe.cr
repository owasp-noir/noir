require "../../../models/analyzer"
require "../../../miniparsers/fsharp_callee_extractor"

module Analyzer::Fsharp
  # Giraffe is a functional web framework on top of ASP.NET Core. Routes
  # are HttpHandler values composed via the `>=>` Kleisli operator and
  # collected with `choose [...]`. Common combinators surfaced here:
  #
  #   * `route "/path"`             — exact path match
  #   * `routeCi "/path"`           — case-insensitive variant
  #   * `routex "regex"`            — regex variant (path is reported verbatim)
  #   * `routef "/users/%i/%s"`     — typed parameters
  #   * `subRoute "/prefix" handler` and friends — mount nested routes
  #
  # HTTP method filters (`GET`, `POST`, etc.) appearing on the same
  # textual line as a route are honored; lines without an explicit
  # method default to a fallback set.
  class Giraffe < Analyzer
    HTTP_METHODS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]

    FALLBACK_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    # Mapping of routef format specifiers to noir path-param types.
    ROUTEF_PARAM_TYPES = {
      'i' => "int",
      'd' => "int64",
      'b' => "bool",
      'c' => "char",
      's' => "string",
      'f' => "float",
      'O' => "guid",
      'u' => "uint64",
    }

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      all_files.each do |path|
        next if File.directory?(path)
        next unless path.ends_with?(".fs") || path.ends_with?(".fsx")
        # Skip .NET test conventions: `/tests/` and `/test/`
        # parent dirs, and `*Tests.fs` filenames. Giraffe's own
        # `tests/Giraffe.Tests/*.fs` accounts for ~218 phantom
        # endpoints — full `webApp` HttpHandler trees built only
        # to exercise the routing combinators.
        next if fsharp_test_path?(path)

        content = read_file_content(path)
        process_file(path, content, include_callee)
      end

      @result
    end

    private def fsharp_test_path?(path : String) : Bool
      return true if path.includes?("/tests/")
      return true if path.includes?("/test/")
      base = File.basename(path)
      return true if base.ends_with?("Tests.fs")
      base.ends_with?("Test.fs")
    end

    alias SubRouteScope = NamedTuple(prefix: String, end_pos: Int32, params: Array(Param))

    private def process_file(path : String, content : String, include_callee : Bool)
      cleaned = strip_fsharp_comments(content)
      scope_stack = [] of SubRouteScope

      i = 0
      while i < cleaned.size
        # Drop sub-route scopes whose closing paren has already passed.
        while !scope_stack.empty? && scope_stack.last[:end_pos] <= i
          scope_stack.pop
        end

        rest = cleaned[i..]

        # subRoute / subRouteCi / subRoutef "/prefix" (handler)
        sub_match = rest.match(/\A(subRoute(?:Ci|f)?)\s+"([^"]+)"\s*\(/)
        if sub_match
          combinator = sub_match[1]
          raw_prefix = sub_match[2]
          match_end_local = sub_match.end(0)
          if match_end_local
            open_paren_abs = i + match_end_local - 1
            close_paren = find_matching_paren(cleaned, open_paren_abs)
            if close_paren
              translated_prefix, prefix_params = if combinator == "subRoutef"
                                                   translate_routef(raw_prefix)
                                                 else
                                                   {raw_prefix, [] of Param}
                                                 end
              scope_stack << {
                prefix:  translated_prefix,
                end_pos: close_paren,
                params:  prefix_params,
              }
              i += match_end_local
              next
            end
          end
        end

        # routef "/users/%i/%s"
        routef_match = rest.match(/\Aroutef\s+"([^"]+)"/)
        if routef_match
          path_pattern = routef_match[1]
          match_end_local = routef_match.end(0)
          emit_route(path, content, cleaned, i, scope_stack, path_pattern, routef: true, include_callee: include_callee)
          i += match_end_local || 1
          next
        end

        # route / routeCi / routex "/path"
        route_match = rest.match(/\A(?:route(?:Ci|x)?)\s+"([^"]+)"/)
        if route_match
          path_pattern = route_match[1]
          match_end_local = route_match.end(0)
          emit_route(path, content, cleaned, i, scope_stack, path_pattern, routef: false, include_callee: include_callee)
          i += match_end_local || 1
          next
        end

        i += 1
      end
    end

    private def current_prefix(scope_stack : Array(SubRouteScope)) : String
      scope_stack.map { |s| s[:prefix] }.join("")
    end

    private def current_prefix_params(scope_stack : Array(SubRouteScope)) : Array(Param)
      params = [] of Param
      scope_stack.each { |s| params.concat(s[:params]) }
      params
    end

    private def emit_route(path : String, content : String, cleaned : String,
                           offset : Int32, scope_stack : Array(SubRouteScope),
                           path_pattern : String, routef : Bool, include_callee : Bool)
      url, params = if routef
                      translate_routef(path_pattern)
                    else
                      {path_pattern, [] of Param}
                    end
      full_url = current_prefix(scope_stack) + url
      full_params = current_prefix_params(scope_stack) + params

      method = find_method_for_route(cleaned, offset)
      methods = method ? [method] : FALLBACK_METHODS

      line = line_for_offset(content, offset)
      details = Details.new(PathInfo.new(path, line))
      callees = include_callee ? callees_for_route(path, content, cleaned, offset) : [] of Noir::FsharpCalleeExtractor::Entry

      methods.each do |verb|
        endpoint_params = full_params.map { |p| Param.new(p.name, p.value, p.param_type) }
        endpoint = Endpoint.new(full_url, verb, endpoint_params, details)
        Noir::FsharpCalleeExtractor.attach_to(endpoint, callees)
        @result << endpoint
      end
    end

    private def callees_for_route(path : String,
                                  content : String,
                                  cleaned : String,
                                  offset : Int32) : Array(Noir::FsharpCalleeExtractor::Entry)
      body_info = route_handler_body(cleaned, offset)
      return [] of Noir::FsharpCalleeExtractor::Entry unless body_info

      body, body_start = body_info
      start_line = line_for_offset(content, body_start)
      Noir::FsharpCalleeExtractor.callees_for_body(body, path, start_line)
    end

    private def route_handler_body(text : String, offset : Int32) : Tuple(String, Int32)?
      body_start = route_pattern_end(text, offset)
      return unless body_start

      route_line_start = line_start_for_offset(text, offset)
      base_indent = indentation_at(text, route_line_start)
      body_end = route_handler_end(text, body_start, base_indent)
      return if body_end <= body_start

      {text[body_start...body_end], body_start}
    end

    private def route_pattern_end(text : String, offset : Int32) : Int32?
      i = offset
      while i < text.size && identifier_char?(text[i])
        i += 1
      end

      while i < text.size && text[i].whitespace?
        i += 1
      end

      return unless i < text.size && text[i] == '"'

      string_end = find_string_end(text, i)
      return unless string_end

      string_end + 1
    end

    private def find_string_end(text : String, quote_index : Int32) : Int32?
      i = quote_index + 1
      escaping = false

      while i < text.size
        char = text[i]
        if escaping
          escaping = false
        elsif char == '\\'
          escaping = true
        elsif char == '"'
          return i
        end
        i += 1
      end

      nil
    end

    private def route_handler_end(text : String, start : Int32, base_indent : Int32) : Int32
      first_line = true
      line_start = line_start_for_offset(text, start)
      cursor = line_start

      while cursor < text.size
        line_end = text.index('\n', cursor) || text.size
        line = text[cursor...line_end]

        if !first_line && route_handler_stop_line?(line, base_indent)
          return cursor
        end

        first_line = false
        cursor = line_end + 1
      end

      text.size
    end

    private def route_handler_stop_line?(line : String, base_indent : Int32) : Bool
      stripped = line.strip
      return false if stripped.empty?

      indent = indentation_of_line(line)
      return false if indent > base_indent
      return true if stripped.starts_with?("]") || stripped.starts_with?(")")
      return true if stripped.match(/\A(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\b\s*$/)

      !!stripped.match(/\A(?:(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\b.*\broute(?:Ci|f|x)?\b|route(?:Ci|f|x)?\b|subRoute(?:Ci|f)?\b)/)
    end

    private def line_start_for_offset(text : String, offset : Int32) : Int32
      return 0 if offset <= 0

      line_start_raw = text.rindex('\n', offset - 1)
      line_start_raw ? line_start_raw + 1 : 0
    end

    private def indentation_at(text : String, line_start : Int32) : Int32
      count = 0
      i = line_start
      while i < text.size
        char = text[i]
        if char == ' '
          count += 1
        elsif char == '\t'
          count += 2
        else
          break
        end
        i += 1
      end
      count
    end

    private def indentation_of_line(line : String) : Int32
      count = 0
      line.each_char do |char|
        if char == ' '
          count += 1
        elsif char == '\t'
          count += 2
        else
          break
        end
      end
      count
    end

    private def identifier_char?(char : Char) : Bool
      char.alphanumeric? || char == '_'
    end

    private def translate_routef(pattern : String) : Tuple(String, Array(Param))
      params = [] of Param
      buffer = String::Builder.new
      i = 0
      counter = Hash(String, Int32).new(0)

      while i < pattern.size
        c = pattern[i]
        if c == '%' && i + 1 < pattern.size
          spec = pattern[i + 1]
          type = ROUTEF_PARAM_TYPES[spec]?
          if type
            counter[type] += 1
            name = counter[type] == 1 ? type : "#{type}_#{counter[type]}"
            buffer << ":#{name}"
            params << Param.new(name, type, "path")
            i += 2
            next
          end
        end
        buffer << c
        i += 1
      end

      {buffer.to_s, params}
    end

    # Walks backwards through `>=>`-connected continuation lines,
    # accumulating preceding text so that an HTTP method filter
    # declared on a previous line still attaches to the route.
    private def find_method_for_route(text : String, route_pos : Int32) : String?
      cursor = route_pos
      collected = String::Builder.new

      loop do
        line_start_raw = cursor > 0 ? text.rindex('\n', cursor - 1) : nil
        line_start = line_start_raw ? line_start_raw + 1 : 0
        line = text[line_start...cursor]
        collected << line
        collected << ' '

        break if line_start == 0

        prev_le = line_start - 1 # position of the '\n' that ended the previous line
        prev_ls_raw = prev_le > 0 ? text.rindex('\n', prev_le - 1) : nil
        prev_ls = prev_ls_raw ? prev_ls_raw + 1 : 0
        prev_line = text[prev_ls...prev_le]
        # Continue across the line break only when the chain is
        # explicitly extended via `>=>` (either trailing or leading).
        if prev_line.rstrip.ends_with?(">=>") || line.lstrip.starts_with?(">=>")
          cursor = prev_le
        else
          break
        end
      end

      window = collected.to_s
      methods = HTTP_METHODS.select { |m| window.match(/\b#{m}\b/) }
      methods.first?
    end

    private def find_matching_paren(text : String, open_idx : Int32) : Int32?
      return unless open_idx < text.size && text[open_idx] == '('
      depth = 1
      i = open_idx + 1
      in_string = false
      string_quote = '\0'

      while i < text.size && depth > 0
        c = text[i]
        if in_string
          if c == '\\' && i + 1 < text.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '('
          depth += 1
        when ')'
          depth -= 1
          return i if depth == 0
        else
          # ignore
        end
        i += 1
      end

      nil
    end

    private def strip_fsharp_comments(text : String) : String
      result = String::Builder.new
      i = 0
      chars = text.chars
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size
            result << c
            result << chars[i + 1]
            i += 2
            next
          elsif c == string_quote
            in_string = false
          end
          result << c
          i += 1
          next
        end

        if c == '"' || c == '\''
          in_string = true
          string_quote = c
          result << c
          i += 1
          next
        end

        # Line comments: //
        if i + 1 < chars.size && c == '/' && chars[i + 1] == '/'
          result << ' '
          result << ' '
          i += 2
          while i < chars.size && chars[i] != '\n'
            result << ' '
            i += 1
          end
          if i < chars.size
            result << chars[i]
            i += 1
          end
          next
        end

        # Block comments: (* ... *) — F# uses these instead of /* */.
        if i + 1 < chars.size && c == '(' && chars[i + 1] == '*'
          depth = 1
          result << ' '
          result << ' '
          i += 2
          while i + 1 < chars.size && depth > 0
            if chars[i] == '(' && chars[i + 1] == '*'
              depth += 1
              result << ' '
              result << ' '
              i += 2
            elsif chars[i] == '*' && chars[i + 1] == ')'
              depth -= 1
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

        result << c
        i += 1
      end

      result.to_s
    end

    private def line_for_offset(content : String, offset : Int32) : Int32
      return 1 if offset <= 0
      limit = offset > content.size ? content.size : offset
      count = 1
      i = 0
      while i < limit
        count += 1 if content[i] == '\n'
        i += 1
      end
      count
    end
  end
end
