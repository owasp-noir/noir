require "../../../models/analyzer"

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
      all_files.each do |path|
        next if File.directory?(path)
        next unless path.ends_with?(".lua") || path.ends_with?(".moon")

        content = read_file_content(path)
        process_file(path, content)
      end

      @result
    end

    private def process_file(path : String, content : String)
      cleaned = strip_lua_comments(content)

      emit_method_calls(path, content, cleaned)
      emit_match_calls(path, content, cleaned)
      emit_table_routes(path, content, cleaned)
      emit_moonscript_routes(path, content, cleaned)
    end

    # `app:get "/path"`, `app:post("/path", handler)`, etc.
    private def emit_method_calls(path : String, content : String, cleaned : String)
      pattern = /\bapp\s*[:.]\s*(get|post|put|delete|patch|head|options)\s*\(?\s*(['"])([^'"]+)\2/
      cleaned.scan(pattern) do |match|
        verb = match[1].upcase
        next unless HTTP_METHODS.includes?(verb)
        url = match[3]
        next unless url.starts_with?("/")
        emit_endpoint(path, content, match.begin(0) || 0, url, [verb])
      end
    end

    # `app:match("/path", handler)` — any HTTP method.
    # `app:match("name", "/path", handler)` — named route.
    private def emit_match_calls(path : String, content : String, cleaned : String)
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
        emit_endpoint(path, content, match.begin(0) || 0, url, FALLBACK_METHODS)
      end
    end

    # `["/path"] = "handler"` and `["/path"] = function(self) ... end`
    # — application-table style.
    private def emit_table_routes(path : String, content : String, cleaned : String)
      pattern = /\[\s*(['"])([^'"]+)\1\s*\]\s*=/
      cleaned.scan(pattern) do |match|
        url = match[2]
        next unless url.starts_with?("/")
        emit_endpoint(path, content, match.begin(0) || 0, url, FALLBACK_METHODS)
      end
    end

    # MoonScript class actions:
    #   "/path": =>
    #   [name: "/path"]: =>
    private def emit_moonscript_routes(path : String, content : String, cleaned : String)
      simple = /(?:^|\n)\s*(['"])([^'"]+)\1\s*:\s*=>/m
      cleaned.scan(simple) do |match|
        url = match[2]
        next unless url.starts_with?("/")
        emit_endpoint(path, content, match.begin(0) || 0, url, FALLBACK_METHODS)
      end

      named = /\[\s*[A-Za-z_]\w*\s*:\s*(['"])([^'"]+)\1\s*\]\s*:\s*=>/
      cleaned.scan(named) do |match|
        url = match[2]
        next unless url.starts_with?("/")
        emit_endpoint(path, content, match.begin(0) || 0, url, FALLBACK_METHODS)
      end
    end

    private def emit_endpoint(path : String, content : String, offset : Int32,
                              url : String, methods : Array(String))
      params = extract_path_params(url)
      line = line_for_offset(content, offset)
      details = Details.new(PathInfo.new(path, line))
      methods.each do |verb|
        endpoint_params = params.map { |p| Param.new(p.name, p.value, p.param_type) }
        @result << Endpoint.new(url, verb, endpoint_params, details)
      end
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
            i += 4
            while i + 1 < chars.size && !(chars[i] == ']' && chars[i + 1] == ']')
              result << '\n' if chars[i] == '\n'
              i += 1
            end
            i += 2 if i + 1 < chars.size
            next
          end
          # Line form
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
