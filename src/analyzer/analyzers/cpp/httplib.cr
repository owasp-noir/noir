require "../../../models/analyzer"
require "../../../miniparsers/cpp_callee_extractor"

module Analyzer::Cpp
  # cpp-httplib (yhirose/cpp-httplib) — a header-only HTTP/HTTPS server & client
  # library. Routes are registered on a `httplib::Server` (or `SSLServer`)
  # instance: `svr.Get("/path", handler)`, `svr.Post`, `Put`, `Delete`,
  # `Patch`, `Options`. The handler is either an inline lambda or a named
  # function. The library's `Client` type shares the same verb method names, so
  # we only treat calls on a *server* variable as routes.
  class Httplib < Analyzer
    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx"]

    VERBS = {
      "Get"     => "GET",
      "Post"    => "POST",
      "Put"     => "PUT",
      "Delete"  => "DELETE",
      "Patch"   => "PATCH",
      "Options" => "OPTIONS",
    }

    # receiver.Verb( — group 1 = receiver variable, group 2 = HTTP verb.
    ROUTE_CALL_REGEX = /\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(Get|Post|Put|Delete|Patch|Options)\s*\(/
    # httplib::Server / Server / SSLServer declarations and reference params.
    SERVER_DECL_QUALIFIED = /\bhttplib::(?:SSL)?Server\s*&?\s*([A-Za-z_][A-Za-z0-9_]*)/
    SERVER_DECL_BARE      = /\b(?:SSL)?Server\s*&?\s*([A-Za-z_][A-Za-z0-9_]*)/
    CLIENT_DECL_QUALIFIED = /\bhttplib::(?:SSL)?Client\s*&?\s*([A-Za-z_][A-Za-z0-9_]*)/
    CLIENT_DECL_BARE      = /\b(?:SSL)?Client\s*&?\s*([A-Za-z_][A-Za-z0-9_]*)/

    # Request accessors mined from a handler body.
    QUERY_ACCESSORS   = /\b(?:get_param_value|has_param|get_file_value)\s*\(\s*"([^"]+)"/
    HEADER_ACCESSORS  = /\b(?:get_header_value|has_header)\s*\(\s*"([^"]+)"/
    PATH_PARAM_ACCESS = /\bpath_params\s*(?:\.\s*at\s*\(\s*|\[\s*)"([^"]+)"/
    BODY_ACCESS       = /\b(?:req|request)\s*\.\s*body\b/
    # `:name` path placeholder (cpp-httplib named params).
    NAMED_PARAM_REGEX = /:([A-Za-z_][A-Za-z0-9_]*)/
    # Regex metacharacters that mark a route pattern as a regex (kept verbatim).
    REGEX_META = /[()\[\]\\+*?^$|]/

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      begin
        locator = CodeLocator.instance
        files = CPP_EXTENSIONS.flat_map { |ext| locator.files_by_extension(ext) }

        parallel_analyze(files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)
          # The vendored single-header library defines the Server/Client classes
          # themselves; never scan it for routes (avoids FPs + a big perf hit).
          next if path.ends_with?("httplib.h") || path.ends_with?("httplib.hpp")
          analyze_file(path, include_callee)
        end
      rescue e
        logger.debug "httplib analyzer failed: #{e.message}"
      end

      result
    end

    private def analyze_file(path : String, include_callee : Bool)
      source = read_file_content(path)
      return unless source.includes?("httplib")
      return unless source.includes?(".Get(") || source.includes?(".Post(") ||
                    source.includes?(".Put(") || source.includes?(".Delete(") ||
                    source.includes?(".Patch(") || source.includes?(".Options(")

      source = Noir::CppCalleeExtractor.strip_comments(source)
      using_ns = source.includes?("using namespace httplib")
      servers = collect_vars(source, SERVER_DECL_QUALIFIED, using_ns ? SERVER_DECL_BARE : nil)
      return if servers.empty?
      clients = collect_vars(source, CLIENT_DECL_QUALIFIED, using_ns ? CLIENT_DECL_BARE : nil)
      servers -= clients

      source.scan(ROUTE_CALL_REGEX) do |match|
        receiver = match[1]
        next unless servers.includes?(receiver)

        verb = VERBS[match[2]]? || next
        call_start = source.char_index_to_byte_index(match.begin(0) || 0) || 0
        open_paren = Noir::CppCalleeExtractor.find_next_code_char(source, '(', call_start)
        next unless open_paren
        close_paren = Noir::CppCalleeExtractor.find_matching_delimiter(source, open_paren, '(', ')')
        next unless close_paren

        args = split_top_level_args(source.byte_slice(open_paren + 1, close_paren - open_paren - 1))
        raw_path = parse_path_arg(args[0]?)
        next unless raw_path

        normalized_path, path_params = normalize_path(raw_path)
        line_number = Noir::CppCalleeExtractor.line_number_for(source, call_start)
        details = Details.new(PathInfo.new(path, line_number))
        endpoint = Endpoint.new(normalized_path, verb, path_params.dup, details)

        handler_block = handler_body(source, args[1]?, open_paren, close_paren)
        if handler_block
          body, start_line = handler_block
          collect_params(body).each { |param| push_unique(endpoint, param) }
          if include_callee
            Noir::CppCalleeExtractor.attach_to(endpoint,
              Noir::CppCalleeExtractor.callees_for_body(body, path, start_line))
          end
        end

        result << endpoint
      end
    end

    # Resolves the handler's body: the inline lambda block when present,
    # otherwise the body of the named function passed as the handler argument.
    private def handler_body(source : String, handler_arg : String?, open_paren : Int32, close_paren : Int32) : Tuple(String, Int32)?
      if block = Noir::CppCalleeExtractor.extract_lambda_block_after(source, open_paren, close_paren)
        return block
      end

      return unless handler_arg
      name = handler_arg.strip.lchop('&').strip
      return unless name.matches?(/\A[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*\z/)
      simple = name.split("::").last
      extract_function_body(source, simple)
    end

    private def extract_function_body(source : String, name : String) : Tuple(String, Int32)?
      regex = /\b#{Regex.escape(name)}\s*\(/
      source.scan(regex) do |match|
        match_start = source.char_index_to_byte_index(match.begin(0) || 0) || 0
        # Skip call sites (`foo.name(`, `obj::name(`); we want the definition.
        prev = previous_code_char(source, match_start)
        next if prev == '.' || prev == '>' || prev == ':'

        open_paren = Noir::CppCalleeExtractor.find_next_code_char(source, '(', match_start)
        next unless open_paren
        close_paren = Noir::CppCalleeExtractor.find_matching_delimiter(source, open_paren, '(', ')')
        next unless close_paren

        body_open = Noir::CppCalleeExtractor.find_next_code_char(source, '{', close_paren + 1)
        next unless body_open
        # A `;` before the `{` means this is a declaration/call, not a definition.
        semicolon = Noir::CppCalleeExtractor.find_next_code_char(source, ';', close_paren + 1)
        next if semicolon && semicolon < body_open

        body_close = Noir::CppCalleeExtractor.find_matching_delimiter(source, body_open, '{', '}')
        next unless body_close
        return {source.byte_slice(body_open + 1, body_close - body_open - 1), Noir::CppCalleeExtractor.line_number_for(source, body_open)}
      end

      nil
    end

    private def previous_code_char(source : String, index : Int32) : Char?
      cursor = index - 1
      while cursor >= 0
        char = source.byte_at(cursor).unsafe_chr
        return char unless char.whitespace?
        cursor -= 1
      end
      nil
    end

    # Collects identifiers declared with the qualified type (always) and the
    # bare type (only when `using namespace httplib` makes it unambiguous).
    private def collect_vars(source : String, qualified : Regex, bare : Regex?) : Set(String)
      vars = Set(String).new
      source.scan(qualified) { |m| vars << m[1] }
      if bare
        source.scan(bare) { |m| vars << m[1] }
      end
      vars
    end

    # First argument of the route call: a normal `"..."` or raw `R"(...)"`
    # string literal. Returns nil for anything else (e.g. a variable).
    private def parse_path_arg(raw : String?) : String?
      return unless raw
      s = raw.strip
      if s.starts_with?("R\"") && (open = s.index('(')) && (close = s.rindex(')'))
        return s[(open + 1)...close] if close > open
      end
      return s[1...-1] if s.size >= 2 && s.starts_with?('"') && s.ends_with?('"')
      nil
    end

    private def normalize_path(raw : String) : Tuple(String, Array(Param))
      # Regex routes are kept verbatim — the captures are positional, with no
      # named placeholders to rewrite.
      return {raw, [] of Param} if raw.matches?(REGEX_META)

      params = [] of Param
      normalized = raw.gsub(NAMED_PARAM_REGEX) do
        name = $1
        params << Param.new(name, "", "path")
        "{#{name}}"
      end
      {normalized, params}
    end

    private def collect_params(body : String) : Array(Param)
      params = [] of Param
      body.each_line do |line|
        line.scan(QUERY_ACCESSORS) { |m| add_param(params, Param.new(m[1], "", "query")) }
        line.scan(HEADER_ACCESSORS) { |m| add_param(params, Param.new(m[1], "", "header")) }
        line.scan(PATH_PARAM_ACCESS) { |m| add_param(params, Param.new(m[1], "", "path")) }
        add_param(params, Param.new("body", "", "json")) if line.matches?(BODY_ACCESS)
      end
      params
    end

    private def add_param(params : Array(Param), param : Param)
      return if param.name.empty?
      return if params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      params << param
    end

    private def push_unique(endpoint : Endpoint, param : Param)
      return if endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      endpoint.push_param(param)
    end

    private def split_top_level_args(raw : String) : Array(String)
      args = [] of String
      current = String::Builder.new
      paren = 0
      brace = 0
      bracket = 0
      in_string = false
      escaped = false

      raw.each_char do |char|
        if in_string
          current << char
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"' then in_string = true
        when '(' then paren += 1
        when ')' then paren -= 1 if paren > 0
        when '{' then brace += 1
        when '}' then brace -= 1 if brace > 0
        when '[' then bracket += 1
        when ']' then bracket -= 1 if bracket > 0
        when ','
          if paren == 0 && brace == 0 && bracket == 0
            args << current.to_s.strip
            current = String::Builder.new
            next
          end
        end

        current << char
      end

      tail = current.to_s.strip
      args << tail unless tail.empty?
      args
    end
  end
end
