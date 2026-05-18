require "../../../models/analyzer"
require "../../../miniparsers/lua_callee_extractor"

module Analyzer::Lua
  # Lapis is a Lua/MoonScript web framework on top of OpenResty. Routes
  # can be expressed in several styles:
  #
  #   * Method-specific calls — `app:get("/path", handler)`,
  #     `app:post`, `app:put`, `app:delete`, `app:patch`,
  #     `app:head`, `app:options`.
  #   * Generic `app:match(path, handler)` and the named
  #     `app:match("name", "/path", handler)` form, both of which
  #     dispatch on any HTTP method.
  #   * Application-table style: `["/path"] = "handler_name"` or
  #     `["/path"] = function(self) ... end`.
  #   * MoonScript class actions: `"/path": =>` and the named form
  #     `[name: "/path"]: =>`.
  #
  # Path parameters use `:name` and splats use `*name`, which already
  # match noir's URL convention so they are surfaced verbatim.
  class Lapis < Analyzer
    HTTP_METHODS     = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]
    FALLBACK_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      all_files.each do |path|
        next if File.directory?(path)
        next unless path.ends_with?(".lua") || path.ends_with?(".moon")
        # Skip Busted / OpenResty spec files. Lapis's own
        # `spec/**/*_spec.moon` and `spec_openresty/`/`spec_cqueues/`
        # trees define ~143 phantom routes against inline test
        # apps. Production Lua never adopts the `_spec` filename
        # or the `spec*/` directory layout.
        next if lapis_test_path?(path)

        content = read_file_content(path)
        process_file(path, content, include_callee)
      end

      @result
    end

    # Busted convention: `<name>_spec.lua` / `<name>_spec.moon`,
    # plus `spec/` / `spec_<variant>/` (e.g. `spec_openresty/`,
    # `spec_cqueues/`) directories at the project root. The
    # filename suffix is unambiguous anywhere in the tree; the
    # directory match is anchored against the configured
    # `base_paths` so our own fixture tree under
    # `spec/functional_test/fixtures/lua/...` doesn't accidentally
    # match.
    private def lapis_test_path?(path : String) : Bool
      base = File.basename(path)
      return true if base.ends_with?("_spec.lua") || base.ends_with?("_spec.moon")
      base_paths.any? do |root|
        normalized = root.ends_with?("/") ? root : "#{root}/"
        tail = path.lchop?(normalized)
        next false unless tail
        first_segment = tail.split("/", 2).first
        first_segment == "spec" || first_segment.starts_with?("spec_")
      end
    end

    private def process_file(path : String, content : String, include_callee : Bool)
      cleaned = strip_lua_comments(content)
      handler_bodies = if include_callee
                         Noir::LuaCalleeExtractor.function_bodies(content, path)
                       else
                         {} of String => Noir::LuaCalleeExtractor::FunctionBody
                       end

      emit_method_calls(path, content, cleaned, include_callee, handler_bodies)
      emit_match_calls(path, content, cleaned, include_callee, handler_bodies)
      emit_table_routes(path, content, cleaned, include_callee, handler_bodies)
      emit_moonscript_routes(path, content, cleaned, include_callee)
    end

    # `app:get "/path"`, `app:post("/path", handler)`, etc.
    private def emit_method_calls(path : String,
                                  content : String,
                                  cleaned : String,
                                  include_callee : Bool,
                                  handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody))
      pattern = /\bapp\s*[:.]\s*(get|post|put|delete|patch|head|options)\s*\(?\s*(['"])([^'"]+)\2/
      cleaned.scan(pattern) do |match|
        verb = match[1].upcase
        next unless HTTP_METHODS.includes?(verb)
        url = match[3]
        next unless url.starts_with?("/")

        route_offset = match.begin(0) || 0
        after_url = match.end(0) || route_offset
        callees = include_callee ? route_call_callees(path, content, route_offset, after_url, handler_bodies) : [] of Noir::LuaCalleeExtractor::Entry
        emit_endpoint(path, content, route_offset, url, [verb], callees)
      end
    end

    # `app:match("/path", handler)` — any HTTP method.
    # `app:match("name", "/path", handler)` — named route.
    private def emit_match_calls(path : String,
                                 content : String,
                                 cleaned : String,
                                 include_callee : Bool,
                                 handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody))
      pattern = /\bapp\s*[:.]\s*match\s*\(?\s*(['"])([^'"]+)\1(?:\s*,\s*(['"])([^'"]+)\3)?/
      cleaned.scan(pattern) do |match|
        first = match[2]
        second = match[4]?
        url = if second && second.starts_with?("/")
                second
              elsif first.starts_with?("/")
                first
              else
                next
              end
        route_offset = match.begin(0) || 0
        url_end = match.end(0) || route_offset
        callees = include_callee ? route_call_callees(path, content, route_offset, url_end, handler_bodies) : [] of Noir::LuaCalleeExtractor::Entry
        emit_endpoint(path, content, route_offset, url, FALLBACK_METHODS, callees)
      end
    end

    # `["/path"] = "handler"` and `["/path"] = function(self) ... end`
    # — application-table style.
    private def emit_table_routes(path : String,
                                  content : String,
                                  cleaned : String,
                                  include_callee : Bool,
                                  handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody))
      pattern = /\[\s*(['"])([^'"]+)\1\s*\]\s*=/
      cleaned.scan(pattern) do |match|
        url = match[2]
        next unless url.starts_with?("/")

        route_offset = match.begin(0) || 0
        after_assignment = match.end(0) || route_offset
        callees = include_callee ? table_route_callees(path, content, after_assignment, handler_bodies) : [] of Noir::LuaCalleeExtractor::Entry
        emit_endpoint(path, content, route_offset, url, FALLBACK_METHODS, callees)
      end
    end

    # MoonScript class actions:
    #   "/path": =>
    #   [name: "/path"]: =>
    private def emit_moonscript_routes(path : String, content : String, cleaned : String, include_callee : Bool)
      simple = /(?:^|\n)\s*(['"])([^'"]+)\1\s*:\s*=>/m
      cleaned.scan(simple) do |match|
        url = match[2]
        next unless url.starts_with?("/")

        route_offset = match.begin(2) || match.begin(0) || 0
        arrow_end = match.end(0) || route_offset
        callees = include_callee ? moonscript_route_callees(path, content, arrow_end) : [] of Noir::LuaCalleeExtractor::Entry
        emit_endpoint(path, content, route_offset, url, FALLBACK_METHODS, callees)
      end

      named = /\[\s*[A-Za-z_]\w*\s*:\s*(['"])([^'"]+)\1\s*\]\s*:\s*=>/
      cleaned.scan(named) do |match|
        url = match[2]
        next unless url.starts_with?("/")

        route_offset = match.begin(2) || match.begin(0) || 0
        arrow_end = match.end(0) || route_offset
        callees = include_callee ? moonscript_route_callees(path, content, arrow_end) : [] of Noir::LuaCalleeExtractor::Entry
        emit_endpoint(path, content, route_offset, url, FALLBACK_METHODS, callees)
      end
    end

    private def emit_endpoint(path : String, content : String, offset : Int32,
                              url : String, methods : Array(String),
                              callees : Array(Noir::LuaCalleeExtractor::Entry) = [] of Noir::LuaCalleeExtractor::Entry)
      params = extract_path_params(url)
      line = line_for_offset(content, offset)
      details = Details.new(PathInfo.new(path, line))
      methods.each do |verb|
        endpoint_params = params.map { |p| Param.new(p.name, p.value, p.param_type) }
        endpoint = Endpoint.new(url, verb, endpoint_params, details)
        Noir::LuaCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
        @result << endpoint
      end
    end

    private def route_call_callees(path : String,
                                   content : String,
                                   route_offset : Int32,
                                   after_url : Int32,
                                   handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody)) : Array(Noir::LuaCalleeExtractor::Entry)
      search_limit, body_limit = route_call_limits(content, route_offset, after_url)
      if body = Noir::LuaCalleeExtractor.extract_function_after(content, after_url, search_limit, body_limit)
        body_text, start_line = body
        return Noir::LuaCalleeExtractor.callees_for_body(body_text, path, start_line)
      end

      if handler_name = string_handler_after(content, after_url, search_limit)
        return callees_for_named_handler(handler_name, handler_bodies)
      end

      if handler_name = identifier_handler_after(content, after_url, search_limit)
        return callees_for_named_handler(handler_name, handler_bodies)
      end

      [] of Noir::LuaCalleeExtractor::Entry
    end

    private def table_route_callees(path : String,
                                    content : String,
                                    after_assignment : Int32,
                                    handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody)) : Array(Noir::LuaCalleeExtractor::Entry)
      value_start = skip_ws(content, after_assignment)
      if starts_with_keyword?(content, value_start, "function")
        if body = Noir::LuaCalleeExtractor.extract_function_at(content, value_start)
          body_text, start_line = body
          return Noir::LuaCalleeExtractor.callees_for_body(body_text, path, start_line)
        end
      elsif handler_name = string_literal_at(content, value_start)
        return callees_for_named_handler(handler_name, handler_bodies)
      end

      [] of Noir::LuaCalleeExtractor::Entry
    end

    private def moonscript_route_callees(path : String, content : String, arrow_end : Int32) : Array(Noir::LuaCalleeExtractor::Entry)
      if body = Noir::LuaCalleeExtractor.extract_moonscript_block_after(content, arrow_end)
        body_text, start_line = body
        return Noir::LuaCalleeExtractor.callees_for_body(body_text, path, start_line)
      end

      [] of Noir::LuaCalleeExtractor::Entry
    end

    private def callees_for_named_handler(handler_name : String,
                                          handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody)) : Array(Noir::LuaCalleeExtractor::Entry)
      if body = handler_bodies[handler_name]?
        return Noir::LuaCalleeExtractor.callees_for_body(body[:body], body[:path], body[:start_line])
      end

      [] of Noir::LuaCalleeExtractor::Entry
    end

    private def route_call_limits(content : String, route_offset : Int32, after_url : Int32) : Tuple(Int32, Int32)
      if open_paren = first_open_paren_before(content, route_offset, after_url)
        if close_paren = Noir::LuaCalleeExtractor.find_matching_delimiter(content, open_paren, '(', ')')
          return {close_paren, close_paren}
        end
      end

      line_end = content.index('\n', after_url) || content.size
      {line_end, content.size}
    end

    private def first_open_paren_before(content : String, start_index : Int32, end_index : Int32) : Int32?
      cursor = start_index
      while cursor < end_index && cursor < content.size
        return cursor if content[cursor] == '('
        cursor += 1
      end

      nil
    end

    private def string_handler_after(content : String, start_index : Int32, limit : Int32) : String?
      cursor = skip_ws_and_commas(content, start_index)
      return if cursor >= limit

      string_literal_at(content, cursor)
    end

    private def identifier_handler_after(content : String, start_index : Int32, limit : Int32) : String?
      cursor = skip_ws_and_commas(content, start_index)
      return if cursor >= limit
      return unless identifier_start?(content[cursor])

      ident_start = cursor
      cursor += 1
      while cursor < limit && cursor < content.size && identifier_part?(content[cursor])
        cursor += 1
      end

      trailing = skip_ws(content, cursor)
      return if trailing < limit && content[trailing] == '('

      content[ident_start...cursor]
    end

    private def string_literal_at(content : String, index : Int32) : String?
      return if index >= content.size
      quote = content[index]
      return unless quote == '"' || quote == '\''

      cursor = index + 1
      escaped = false
      value = String::Builder.new
      while cursor < content.size
        char = content[cursor]
        if escaped
          value << char
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == quote
          return value.to_s
        else
          value << char
        end
        cursor += 1
      end

      nil
    end

    private def skip_ws_and_commas(content : String, index : Int32) : Int32
      cursor = index
      while cursor < content.size && (content[cursor].whitespace? || content[cursor] == ',')
        cursor += 1
      end
      cursor
    end

    private def skip_ws(content : String, index : Int32) : Int32
      cursor = index
      while cursor < content.size && content[cursor].whitespace?
        cursor += 1
      end
      cursor
    end

    private def starts_with_keyword?(content : String, index : Int32, keyword : String) : Bool
      return false unless content[index, keyword.size]? == keyword
      before = index > 0 ? content[index - 1] : '\0'
      after_index = index + keyword.size
      after = after_index < content.size ? content[after_index] : '\0'
      !identifier_part?(before) && !identifier_part?(after)
    end

    private def identifier_start?(char : Char) : Bool
      char.ascii_letter? || char == '_'
    end

    private def identifier_part?(char : Char) : Bool
      char.ascii_alphanumeric? || char == '_'
    end

    private def extract_path_params(url : String) : Array(Param)
      params = [] of Param
      url.scan(/[:*]([A-Za-z_]\w*)/) do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end

    private def strip_lua_comments(text : String) : String
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

        # Lua / MoonScript line comment: --
        # MoonScript also supports `--` and Lua block comments use --[[ ... ]]
        if i + 1 < chars.size && c == '-' && chars[i + 1] == '-'
          # Block form: --[[ ... ]]
          if i + 3 < chars.size && chars[i + 2] == '[' && chars[i + 3] == '['
            4.times { result << ' ' }
            i += 4
            while i + 1 < chars.size && !(chars[i] == ']' && chars[i + 1] == ']')
              result << (chars[i] == '\n' ? '\n' : ' ')
              i += 1
            end
            if i + 1 < chars.size
              2.times { result << ' ' }
              i += 2
            end
            next
          end
          # Line form
          while i < chars.size && chars[i] != '\n'
            result << ' '
            i += 1
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
