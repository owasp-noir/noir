require "../../../models/analyzer"
require "../../../miniparsers/cpp_callee_extractor"
require "wait_group"

module Analyzer::Cpp
  class Drogon < Analyzer
    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp"]
    alias HandlerTarget = Tuple(String?, String)
    alias SourceRange = Tuple(Int32, Int32)
    # A controller class body span plus the URL prefix Drogon derives from its
    # fully-qualified name (namespaces + class), e.g. `api::v1::ApiTest` → `/api/v1/ApiTest`.
    alias ControllerScope = Tuple(Int32, Int32, String)

    HTTP_METHODS = {
      "Get"     => "GET",
      "Post"    => "POST",
      "Put"     => "PUT",
      "Delete"  => "DELETE",
      "Patch"   => "PATCH",
      "Head"    => "HEAD",
      "Options" => "OPTIONS",
    }

    # `{Get, Post}` method list: brace block whose first token is a verb.
    METHOD_BLOCK = /\{\s*((?:drogon::)?(?:Get|Post|Put|Delete|Patch|Head|Options)\b[^{}]*)\}/

    REGEX_REGISTER_HANDLER = /app\(\)\s*\.?\s*registerHandler(?:ViaRegex)?\s*\(\s*"([^"]+)"/

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The macro set is fixed, so precompile its
    # matchers once; the method/class matchers interpolate discovered names
    # and are memoized per name instead.
    MACRO_CALL_PATTERNS = {
      "METHOD_ADD"            => /\bMETHOD_ADD\s*\(/,
      "ADD_METHOD_TO"         => /\bADD_METHOD_TO\s*\(/,
      "ADD_METHOD_VIA_REGEX"  => /\bADD_METHOD_VIA_REGEX\s*\(/,
      "PATH_ADD"              => /\bPATH_ADD\s*\(/,
      "WS_PATH_ADD"           => /\bWS_PATH_ADD\s*\(/,
      "WS_ADD_PATH_VIA_REGEX" => /\bWS_ADD_PATH_VIA_REGEX\s*\(/,
    }
    @method_def_regexes = Hash(String, Regex).new
    @class_decl_regexes = Hash(String, Regex).new

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      begin
        locator = CodeLocator.instance
        files = CPP_EXTENSIONS.flat_map { |ext| locator.files_by_extension(ext) }

        parallel_analyze(files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)
          next unless CPP_EXTENSIONS.any? { |ext| path.ends_with?(ext) }

          content = read_file_content(path)
          next unless content.includes?("drogon") ||
                      content.includes?("registerHandler") ||
                      content.includes?("PATH_LIST_BEGIN") ||
                      content.includes?("PATH_ADD") ||
                      content.includes?("METHOD_LIST_BEGIN") ||
                      content.includes?("METHOD_ADD") ||
                      content.includes?("ADD_METHOD_TO") ||
                      content.includes?("ADD_METHOD_VIA_REGEX")

          analyze_file(path, content, include_callee)
        end
      rescue e
        logger.debug "Drogon analyzer failed: #{e.message}"
      end

      @result
    end

    def analyze_file(path : String, content : String, include_callee : Bool = false)
      # Blank out comments first so commented-out routes and documentation
      # examples (e.g. `/** ADD_METHOD_TO(...) */`) are never mistaken for code.
      content = Noir::CppCalleeExtractor.strip_comments(content)
      lines = content.split("\n")
      file_params = extract_params(lines)

      extract_register_handler_endpoints(path, content, lines, file_params, include_callee).each do |endpoint|
        @result << endpoint
      end

      extract_macro_endpoints(path, content, file_params, include_callee).each do |endpoint|
        @result << endpoint
      end
    end

    private def extract_register_handler_endpoints(path : String, content : String, lines : Array(String), file_params : Array(Param), include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint

      # For each registerHandler("/path") occurrence, look ahead in the content
      # for the nearest method list block `{Get, Post, ...}`. This tolerates
      # lambda bodies between the path and the method list without needing a
      # full-blown C++ parser.
      content.scan(REGEX_REGISTER_HANDLER) do |match|
        raw_route = match[1]
        via_regex = (match[0].includes?("registerHandlerViaRegex"))
        clean_path, path_params, query_params = normalize_drogon_path(raw_route, via_regex)
        rest = match.post_match
        window = rest.size > 4000 ? rest[0, 4000] : rest

        methods = if block_match = window.match(METHOD_BLOCK)
                    parse_methods(block_match[1])
                  else
                    ["GET"]
                  end

        match_start = (content.char_index_to_byte_index(match.begin(0) || 0)) || 0
        line_number = Noir::CppCalleeExtractor.line_number_for(content, match_start)
        callees = include_callee ? callees_for_block_after(content, path, match_start) : [] of Noir::CppCalleeExtractor::Entry
        route_params = params_for_register_handler(content, match_start)

        methods.each do |m|
          details = Details.new(PathInfo.new(path, line_number))
          endpoint = Endpoint.new(clean_path, m, details)
          path_params.each { |p| add_endpoint_param(endpoint, p) }
          query_params.each { |p| add_endpoint_param(endpoint, p) }
          route_params.each { |p| add_endpoint_param(endpoint, p) }
          Noir::CppCalleeExtractor.attach_to(endpoint, callees) if include_callee
          endpoints << endpoint
        end
      end

      endpoints
    end

    # Handles the controller-style routing macros, all of which may span
    # several lines (Drogon's own clang-format wraps them). Each macro call is
    # located by name and its arguments parsed against balanced parentheses, so
    # multi-line invocations are extracted reliably:
    #
    #   METHOD_ADD(Ctrl::fn, "/path", Get)        — relative to the controller path
    #   ADD_METHOD_TO(Ctrl::fn, "/path", Get)     — absolute path
    #   ADD_METHOD_VIA_REGEX(Ctrl::fn, "/re", Get)— absolute regex path
    #   PATH_ADD("/path", Get)                    — HttpSimpleController, absolute path
    private def extract_macro_endpoints(path : String, content : String, file_params : Array(Param), include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      scopes = controller_scopes(content)

      # METHOD_ADD: path is relative to the controller class path prefix.
      each_macro_call(content, "METHOD_ADD") do |args, call_start|
        next if args.size < 2
        raw_path = unquote(args[1])
        next unless raw_path
        handler = normalize_handler_target(args[0])
        full = join_controller_path(prefix_for(scopes, call_start), raw_path)
        add_macro_endpoints(endpoints, path, content, full, args[2..], handler, file_params, include_callee, call_start)
      end

      # ADD_METHOD_TO: absolute path.
      each_macro_call(content, "ADD_METHOD_TO") do |args, call_start|
        next if args.size < 2
        raw_path = unquote(args[1])
        next unless raw_path
        handler = normalize_handler_target(args[0])
        add_macro_endpoints(endpoints, path, content, raw_path, args[2..], handler, file_params, include_callee, call_start)
      end

      # ADD_METHOD_VIA_REGEX: absolute regex path.
      each_macro_call(content, "ADD_METHOD_VIA_REGEX") do |args, call_start|
        next if args.size < 2
        raw_path = unquote(args[1])
        next unless raw_path
        handler = normalize_handler_target(args[0])
        add_macro_endpoints(endpoints, path, content, raw_path, args[2..], handler, file_params, include_callee, call_start, via_regex: true)
      end

      # PATH_ADD: HttpSimpleController, absolute path, no handler reference.
      each_macro_call(content, "PATH_ADD") do |args, call_start|
        next if args.empty?
        raw_path = unquote(args[0])
        next unless raw_path
        add_macro_endpoints(endpoints, path, content, raw_path, args[1..], nil, file_params, include_callee, call_start)
      end

      # WS_PATH_ADD: WebSocketController, absolute path, upgrade is an HTTP GET.
      each_macro_call(content, "WS_PATH_ADD") do |args, call_start|
        next if args.empty?
        raw_path = unquote(args[0])
        next unless raw_path
        add_macro_endpoints(endpoints, path, content, raw_path, args[1..], nil, file_params, include_callee, call_start, protocol: "ws")
      end

      # WS_ADD_PATH_VIA_REGEX: WebSocketController, absolute regex path.
      each_macro_call(content, "WS_ADD_PATH_VIA_REGEX") do |args, call_start|
        next if args.empty?
        raw_path = unquote(args[0])
        next unless raw_path
        add_macro_endpoints(endpoints, path, content, raw_path, args[1..], nil, file_params, include_callee, call_start, via_regex: true, protocol: "ws")
      end

      endpoints
    end

    private def add_macro_endpoints(endpoints : Array(Endpoint),
                                    path : String,
                                    content : String,
                                    raw_path : String,
                                    method_args : Array(String),
                                    handler : HandlerTarget?,
                                    file_params : Array(Param),
                                    include_callee : Bool,
                                    call_start : Int32,
                                    via_regex : Bool = false,
                                    protocol : String = "http")
      clean_path, path_params, query_params = normalize_drogon_path(raw_path, via_regex)
      methods = parse_methods(method_args.reject(&.lstrip.starts_with?('"')).join(","))
      line_number = Noir::CppCalleeExtractor.line_number_for(content, call_start)

      if handler && !handler[1].empty?
        handler_params = params_for_handler(content, handler)
        handler_callees = include_callee ? callees_for_handler(content, path, handler) : [] of Noir::CppCalleeExtractor::Entry
      else
        # HttpSimpleController (PATH_ADD) has a single fixed handler, so the
        # best available signal is the parameters seen anywhere in the file.
        handler_params = file_params
        handler_callees = [] of Noir::CppCalleeExtractor::Entry
      end

      methods.each do |m|
        details = Details.new(PathInfo.new(path, line_number))
        endpoint = Endpoint.new(clean_path, m, details)
        endpoint.protocol = protocol unless protocol == "http"
        path_params.each { |p| add_endpoint_param(endpoint, p) }
        query_params.each { |p| add_endpoint_param(endpoint, p) }
        handler_params.each { |p| add_endpoint_param(endpoint, p) }
        Noir::CppCalleeExtractor.attach_to(endpoint, handler_callees) if include_callee
        endpoints << endpoint
      end
    end

    private def each_macro_call(content : String, macro_name : String, &block : Array(String), Int32 ->)
      macro_regex = MACRO_CALL_PATTERNS[macro_name]? || /\b#{macro_name}\s*\(/
      content.scan(macro_regex) do |match|
        call_start = (content.char_index_to_byte_index(match.begin(0) || 0)) || 0
        open_paren = Noir::CppCalleeExtractor.find_next_code_char(content, '(', call_start)
        next unless open_paren

        close_paren = Noir::CppCalleeExtractor.find_matching_delimiter(content, open_paren, '(', ')')
        next unless close_paren

        args = split_top_level_args(content.byte_slice(open_paren + 1, close_paren - open_paren - 1))
        block.call(args, call_start)
      end
    end

    private def unquote(raw : String) : String?
      s = raw.strip
      return unless s.size >= 2 && s.starts_with?('"') && s.ends_with?('"')
      s[1...-1]
    end

    # Drogon prefixes METHOD_ADD paths with the controller's fully-qualified
    # name (namespaces joined by `/`, then the class name). Empty patterns map
    # to the bare prefix; relative patterns are appended with a separator.
    private def join_controller_path(prefix : String?, pattern : String) : String
      if prefix.nil?
        return pattern.starts_with?("/") ? pattern : "/#{pattern}"
      end

      if pattern.empty?
        prefix
      elsif pattern.starts_with?("/")
        prefix + pattern
      else
        "#{prefix}/#{pattern}"
      end
    end

    private def prefix_for(scopes : Array(ControllerScope), pos : Int32) : String?
      best : ControllerScope? = nil
      scopes.each do |scope|
        open_brace, close_brace, _ = scope
        next unless pos > open_brace && pos < close_brace
        best = scope if best.nil? || (close_brace - open_brace) < (best[1] - best[0])
      end
      best.try &.[2]
    end

    # Collects every class/struct body in the file together with the URL prefix
    # Drogon would derive for a controller of that name.
    private def controller_scopes(content : String) : Array(ControllerScope)
      scopes = [] of ControllerScope
      content.scan(/\b(?:class|struct)\s+([A-Za-z_][A-Za-z0-9_]*)\b/) do |match|
        class_start = (content.char_index_to_byte_index(match.begin(0) || 0)) || 0
        open_brace = Noir::CppCalleeExtractor.find_next_code_char(content, '{', class_start)
        next unless open_brace

        # Skip forward declarations (`class Foo;`) and `using`/typedef noise.
        semicolon = Noir::CppCalleeExtractor.find_next_code_char(content, ';', class_start)
        next if semicolon && semicolon < open_brace

        close_brace = Noir::CppCalleeExtractor.find_matching_delimiter(content, open_brace, '{', '}')
        next unless close_brace

        namespaces = enclosing_namespaces(content, class_start)
        prefix = "/" + (namespaces + [match[1]]).join("/")
        scopes << {open_brace, close_brace, prefix}
      end
      scopes
    end

    private def enclosing_namespaces(content : String, target : Int32) : Array(String)
      found = [] of Tuple(Int32, String)
      content.scan(/\bnamespace\s+([A-Za-z_][A-Za-z0-9_]*(?:\s*::\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*\{/) do |match|
        ns_start = (content.char_index_to_byte_index(match.begin(0) || 0)) || 0
        open_brace = Noir::CppCalleeExtractor.find_next_code_char(content, '{', ns_start)
        next unless open_brace
        next if open_brace >= target

        close_brace = Noir::CppCalleeExtractor.find_matching_delimiter(content, open_brace, '{', '}')
        next unless close_brace
        next unless target > open_brace && target < close_brace

        found << {open_brace, match[1].gsub(/\s+/, "")}
      end

      found.sort_by!(&.[0])
      found.flat_map { |_, name| name.split("::") }
    end

    private def callees_for_block_after(content : String, path : String, search_start : Int32) : Array(Noir::CppCalleeExtractor::Entry)
      block = Noir::CppCalleeExtractor.extract_block_after(content, search_start)
      return [] of Noir::CppCalleeExtractor::Entry unless block

      body, start_line = block
      Noir::CppCalleeExtractor.callees_for_body(body, path, start_line)
    end

    private def params_for_register_handler(content : String, search_start : Int32) : Array(Param)
      if params = params_for_inline_register_handler(content, search_start)
        return params unless params.empty?
      end

      handler_target = handler_target_for_register_handler(content, search_start)
      return [] of Param unless handler_target

      params_for_handler(content, handler_target)
    end

    private def params_for_inline_register_handler(content : String, search_start : Int32) : Array(Param)?
      block = Noir::CppCalleeExtractor.extract_block_after(content, search_start)
      return unless block

      body, _ = block
      extract_params(body.lines)
    end

    private def params_for_handler(content : String, handler_target : HandlerTarget) : Array(Param)
      block = extract_method_body(content, handler_target)
      return [] of Param unless block

      body, _ = block
      extract_params(body.lines)
    end

    private def handler_target_for_register_handler(content : String, search_start : Int32) : HandlerTarget?
      # search_start is a BYTE offset; byte_index keeps it in byte space so the
      # result feeds the byte-based find_next_code_char below consistently.
      handler_index = content.byte_index("registerHandler", search_start)
      return unless handler_index

      open_paren = Noir::CppCalleeExtractor.find_next_code_char(content, '(', handler_index)
      return unless open_paren

      close_paren = Noir::CppCalleeExtractor.find_matching_delimiter(content, open_paren, '(', ')')
      return unless close_paren

      args = split_top_level_args(content.byte_slice(open_paren + 1, close_paren - open_paren - 1))
      return if args.size < 2

      raw_handler = args[1].strip
      return if raw_handler.empty?
      return if raw_handler.includes?("[]") || raw_handler.includes?("lambda")

      normalize_handler_target(raw_handler)
    end

    private def split_top_level_args(raw : String) : Array(String)
      args = [] of String
      current = String::Builder.new
      paren_depth = 0
      brace_depth = 0
      bracket_depth = 0
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
        when '"'
          in_string = true
        when '('
          paren_depth += 1
        when ')'
          paren_depth -= 1 if paren_depth > 0
        when '{'
          brace_depth += 1
        when '}'
          brace_depth -= 1 if brace_depth > 0
        when '['
          bracket_depth += 1
        when ']'
          bracket_depth -= 1 if bracket_depth > 0
        when ','
          if paren_depth == 0 && brace_depth == 0 && bracket_depth == 0
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

    private def callees_for_handler(content : String, path : String, handler_target : HandlerTarget) : Array(Noir::CppCalleeExtractor::Entry)
      block = extract_method_body(content, handler_target)
      return [] of Noir::CppCalleeExtractor::Entry unless block

      body, start_line = block
      Noir::CppCalleeExtractor.callees_for_body(body, path, start_line)
    end

    private def extract_method_body(content : String, handler_target : HandlerTarget) : Tuple(String, Int32)?
      owner, method_name = handler_target
      return if method_name.empty?

      if owner
        class_range = class_body_range(content, owner)
        if class_range
          body = extract_method_body_in_range(content, Regex.escape(method_name), class_range)
          return body if body
        end

        extract_method_body_in_range(content, "#{Regex.escape(owner)}\\s*::\\s*#{Regex.escape(method_name)}", {0, content.bytesize})
      else
        extract_method_body_in_range(content, Regex.escape(method_name), {0, content.bytesize})
      end
    end

    private def extract_method_body_in_range(content : String, method_pattern : String, range : SourceRange) : Tuple(String, Int32)?
      range_start, range_end = range
      method_regex = @method_def_regexes[method_pattern] ||= /\b#{method_pattern}\s*\(/
      content.scan(method_regex) do |match|
        match_start = (content.char_index_to_byte_index(match.begin(0) || 0)) || 0
        next if match_start < range_start || match_start >= range_end
        next if call_context?(content, match_start)

        open_paren = Noir::CppCalleeExtractor.find_next_code_char(content, '(', match_start)
        next unless open_paren

        close_paren = Noir::CppCalleeExtractor.find_matching_delimiter(content, open_paren, '(', ')')
        next unless close_paren

        body_open = Noir::CppCalleeExtractor.find_next_code_char(content, '{', close_paren + 1)
        next unless body_open
        next if body_open > range_end
        next unless method_suffix?(content.byte_slice(close_paren + 1, body_open - close_paren - 1))

        semicolon = Noir::CppCalleeExtractor.find_next_code_char(content, ';', close_paren + 1)
        next if semicolon && semicolon < body_open

        body_close = Noir::CppCalleeExtractor.find_matching_delimiter(content, body_open, '{', '}')
        next unless body_close

        return {content.byte_slice(body_open + 1, body_close - body_open - 1), Noir::CppCalleeExtractor.line_number_for(content, body_open)}
      end

      nil
    end

    private def class_body_range(content : String, class_name : String) : SourceRange?
      class_regex = @class_decl_regexes[class_name] ||= /\b(?:class|struct)\s+#{Regex.escape(class_name)}\b/
      content.scan(class_regex) do |match|
        class_start = (content.char_index_to_byte_index(match.begin(0) || 0)) || 0
        open_brace = Noir::CppCalleeExtractor.find_next_code_char(content, '{', class_start)
        next unless open_brace

        close_brace = Noir::CppCalleeExtractor.find_matching_delimiter(content, open_brace, '{', '}')
        next unless close_brace

        return {open_brace + 1, close_brace}
      end

      nil
    end

    private def method_suffix?(suffix : String) : Bool
      normalized = suffix.gsub(/noexcept\s*\([^)]*\)/, "noexcept")
      normalized.matches?(/\A[\sA-Za-z0-9_:<>,*&\-\[\]]*\z/)
    end

    private def call_context?(content : String, index : Int32) : Bool
      previous = previous_code_char(content, index)
      previous == '(' || previous == '.' || previous == '>' || previous == ':'
    end

    private def previous_code_char(content : String, index : Int32) : Char?
      cursor = index - 1
      while cursor >= 0
        char = content.byte_at(cursor).unsafe_chr
        return char unless char.whitespace?

        cursor -= 1
      end

      nil
    end

    private def normalize_handler_target(raw : String) : HandlerTarget
      target = raw.strip.lchop('&').strip
      parts = target.split("::").map(&.strip).reject(&.empty?)
      method_name = parts.last? || target
      owner = parts.size > 1 ? parts[-2] : nil
      {owner, method_name}
    end

    private def parse_methods(raw : String) : Array(String)
      methods = [] of String
      raw.split(",").each do |token|
        # Drogon accepts the verb list either as varargs (`Get, Post`) or wrapped
        # in a brace init-list (`{Get, Post}`); strip braces so both forms parse.
        name = token.delete("{}").strip
          .gsub(/^drogon::/, "")
          .gsub(/^HttpMethod::/, "")
          .gsub(/^Http/, "")
          .gsub(/Method$/, "")
          .downcase.capitalize
        next if name.empty?
        if mapped = HTTP_METHODS[name]?
          methods << mapped unless methods.includes?(mapped)
        end
      end
      methods << "GET" if methods.empty?
      methods
    end

    # Splits a Drogon path pattern into a clean URL, its path params, and any
    # query params declared via the `?key={}` suffix. Placeholder bodies are
    # normalized to readable names:
    #   {}            → param1, param2, …   (positional)
    #   {1} / {2}     → param1, param2, …   (positional index)
    #   {int p1}      → p1                  (type + name)
    #   {3:p3}        → p3                  (index : name)
    #   {id}          → id                  (named)
    private def normalize_drogon_path(raw : String, via_regex : Bool = false) : Tuple(String, Array(Param), Array(Param))
      # Regex routes are kept verbatim: `?` is a quantifier / `(?:...)` group,
      # not the query-string separator, so neither splitting nor placeholder
      # rewriting applies.
      return {raw, [] of Param, [] of Param} if via_regex

      path_part, _, query = raw.partition('?')
      query_params = extract_query_params(query)

      path_params = [] of Param
      counter = 0
      clean = path_part.gsub(/\{([^{}]*)\}/) do
        name = clean_param_name($1)
        if name.nil?
          counter += 1
          name = "param#{counter}"
        end
        path_params << Param.new(name, "", "path")
        "{#{name}}"
      end

      {clean, path_params, query_params}
    end

    private def clean_param_name(inner : String) : String?
      s = inner.strip
      return if s.empty?

      # Drogon's colon form is ambiguous: `{id:int}` is name:type (use the
      # name), while `{4:p4}` is index:name (use the name after the index).
      if s.includes?(':')
        before, _, after = s.partition(':')
        before = before.strip
        after = after.strip
        s = before.matches?(/\A\d+\z/) ? after : before
      end

      # `{int p1}` (type + name) collapses to the trailing identifier.
      s = s.split(/\s+/).last if s.includes?(' ')

      return if s.empty? || s.matches?(/\A\d+\z/)
      s
    end

    private def extract_query_params(query : String) : Array(Param)
      params = [] of Param
      return params if query.empty?

      query.split('&').each do |pair|
        key = pair.split('=', 2).first.strip
        next if key.empty?
        add_unique_param(params, Param.new(key, "", "query"))
      end
      params
    end

    private def extract_params(lines : Array(String)) : Array(Param)
      params = [] of Param

      lines.each do |line|
        if match = line.match(/->\s*getParameter\s*\(\s*"([^"]+)"/)
          add_unique_param(params, Param.new(match[1], "", "query"))
        end

        if match = line.match(/->\s*getOptionalParameter\s*<[^>]*>\s*\(\s*"([^"]+)"/)
          add_unique_param(params, Param.new(match[1], "", "query"))
        end

        if match = line.match(/->\s*getHeader\s*\(\s*"([^"]+)"/)
          add_unique_param(params, Param.new(match[1], "", "header"))
        end

        if match = line.match(/->\s*getCookie\s*\(\s*"([^"]+)"/)
          add_unique_param(params, Param.new(match[1], "", "cookie"))
        end

        if line.includes?("->getJsonObject(") || line.includes?("->getJsonValue(")
          add_unique_param(params, Param.new("body", "", "json"))
        end

        if line.matches?(/->\s*(body|getBody)\s*\(\s*\)/) &&
           !line.includes?("->getJsonObject(") && !line.includes?("->getJsonValue(")
          add_unique_param(params, Param.new("body", "", "body"))
        end
      end

      params
    end

    private def add_unique_param(params : Array(Param), param : Param)
      return if param.name.empty?
      return if params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      params << param
    end

    private def add_endpoint_param(endpoint : Endpoint, param : Param)
      return if param.name.empty?
      return if endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      endpoint.push_param(param)
    end
  end
end
